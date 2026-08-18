create or replace package body road_ctx_pkg as

  -- Namespace names are limited to 30 bytes, so this is the prefix plus as much of the schema name
  -- as fits. A schema name long enough to be truncated into a collision would fail loudly at deploy
  -- time -- dbms_session raises ORA-01031 when the namespace belongs to another schema's package --
  -- rather than silently sharing state, which is the failure mode that matters.
  c_namespace   constant varchar2(30)  :=
    substr('ROAD_CTX_' || sys_context('USERENV', 'CURRENT_SCHEMA'), 1, 30);

  -- Fixed attributes.
  c_attr_established  constant varchar2(30) := 'ESTABLISHED';
  c_attr_principal_id constant varchar2(30) := 'PRINCIPAL_ID';
  c_attr_subject      constant varchar2(30) := 'SUBJECT';
  c_attr_issuer       constant varchar2(30) := 'ISSUER';

  -- Roles and permissions are stored one attribute each, prefixed to keep them out of the fixed
  -- attribute space. Verified on ADB: context attribute names accept up to 128 bytes, so a 64-char
  -- role or permission name plus a 5-char prefix fits with room to spare. The alternative -- packing
  -- a delimited list into one 4000-byte value -- would have imposed a ceiling on how many
  -- permissions a role may compose, and needed parsing on every check.
  c_prefix_role constant varchar2(5) := 'ROLE$';
  c_prefix_perm constant varchar2(5) := 'PERM$';

  -- SYS_CONTEXT truncates at 256 bytes unless an explicit length is passed. issuer is
  -- varchar2(512 char) and subject varchar2(255 char), so the length argument is mandatory here,
  -- not defensive: without it a long issuer silently comes back truncated and no principal ever
  -- matches. Verified on dev -- a 1000-byte value read back as 256 without it, 1000 with it.
  c_len_issuer  constant pls_integer := 512;
  c_len_subject constant pls_integer := 255;

  -- Reads the issuer from the schema's own ORDS JWT profile. Correct only while trust is
  -- schema-level with a single profile; 99_verify asserts exactly one row for that reason. See
  -- planning/spike-06-1-iss-reachability.md section 4 for the constraint and the migration path.
  function resolve_issuer return varchar2 is
    l_issuer varchar2(512 char);
  begin
    select issuer into l_issuer from user_ords_jwt_profile;
    return l_issuer;
  exception
    -- Zero profiles or more than one: both are unresolvable, and guessing would be worse than
    -- denying. Fail closed.
    when others then
      return null;
  end resolve_issuer;

  function namespace return varchar2 is
  begin
    return c_namespace;
  end namespace;

  function config_value(p_key in varchar2) return varchar2 is
    l_value road_config.config_value%type;
  begin
    select config_value into l_value from road_config where config_key = p_key;
    return l_value;
  exception
    when no_data_found then
      return null;
  end config_value;

  -- Creates a principal for a subject the issuer has authenticated but this application has never
  -- seen, and grants it road_config.default_principal_role.
  --
  -- Gated on road_config.auto_provision_principals = 'Y'. Off means an unknown subject is denied,
  -- which is rule 3's default; on means the issuer is trusted to decide who exists. That is a
  -- posture decision per deployment, not a mechanism, which is why it is a row rather than code.
  --
  -- Returns the principal_id, or null when provisioning is off or fails.
  function provision_principal(
    p_issuer  in varchar2,
    p_subject in varchar2
  ) return number is
    pragma autonomous_transaction;
    l_principal_id number;
    l_role         road_config.config_value%type;
  begin
    if nvl(config_value('auto_provision_principals'), 'N') != 'Y' then
      rollback;
      return null;
    end if;

    l_role := config_value('default_principal_role');

    begin
      insert into road_principals (issuer, subject, display_name)
      values (p_issuer, p_subject, p_subject)
      returning principal_id into l_principal_id;
    exception
      when dup_val_on_index then
        -- Two first requests for the same new subject can race. The unique constraint on
        -- (issuer, subject) is what makes that safe: the loser reads the winner's row rather than
        -- failing the request, so a genuine user is never denied because they arrived twice at once.
        rollback;
        select principal_id into l_principal_id
          from road_principals
         where issuer = p_issuer and subject = p_subject;
        return l_principal_id;
    end;

    -- No default role configured, or it has been deleted: the principal exists but holds nothing.
    -- Fail closed -- an account with no permissions is recoverable by an administrator, whereas
    -- silently substituting some other role would not be.
    if l_role is not null then
      begin
        insert into road_principal_roles (principal_id, role_name)
        values (l_principal_id, l_role);
      exception
        when others then
          null;
      end;
    end if;

    -- Autonomous so the new principal survives even if the request that triggered it later rolls
    -- back. Otherwise a failing first request would leave the user unprovisioned and they would hit
    -- the same path again on every retry.
    commit;
    return l_principal_id;
  exception
    when others then
      rollback;
      return null;
  end provision_principal;

  procedure end_request is
  begin
    dbms_session.clear_all_context(c_namespace);
  end end_request;

  function begin_request(
    p_subject in varchar2,
    p_issuer  in varchar2 default null
  ) return boolean is
    l_issuer       varchar2(512 char);
    l_subject      varchar2(255 char);
    l_principal_id number;
    l_status       varchar2(20 char);
  begin
    -- 1. Clear FIRST, unconditionally, before any validation. ORDS pools connections, so this
    --    session may still be carrying the previous caller's principal and permissions. Clearing
    --    up front means every failure path below -- including an exception -- leaves the session
    --    holding nothing rather than holding somebody else.
    dbms_session.clear_all_context(c_namespace);

    l_subject := trim(p_subject);
    if l_subject is null then
      return false;
    end if;

    l_issuer := nvl(p_issuer, resolve_issuer);
    if l_issuer is null then
      return false;
    end if;

    begin
      select principal_id, status
        into l_principal_id, l_status
        from road_principals
       where issuer = l_issuer
         and subject = l_subject;
    exception
      when no_data_found then
        -- The issuer authenticated them; this application has simply never seen them before.
        l_principal_id := provision_principal(l_issuer, l_subject);
        if l_principal_id is null then
          return false;
        end if;
        l_status := 'ACTIVE';
    end;

    -- 2. Only ACTIVE principals get a session. SUSPENDED and RETIRED authenticate at ORDS -- their
    --    token is still valid -- and are denied here.
    if l_status != 'ACTIVE' then
      return false;
    end if;

    dbms_session.set_context(c_namespace, c_attr_principal_id, to_char(l_principal_id));
    dbms_session.set_context(c_namespace, c_attr_subject, l_subject);
    dbms_session.set_context(c_namespace, c_attr_issuer, l_issuer);

    -- 3. Roles and effective permissions, loaded once. Permissions are the union across the
    --    principal's roles with no hierarchy (rule 2), so a plain DISTINCT join is the whole rule.
    for r in (
      select role_name
        from road_principal_roles
       where principal_id = l_principal_id
    ) loop
      dbms_session.set_context(c_namespace, c_prefix_role || r.role_name, 'Y');
    end loop;

    for p in (
      select distinct rp.permission_name
        from road_principal_roles pr
        join road_role_permissions rp
          on rp.role_name = pr.role_name
       where pr.principal_id = l_principal_id
    ) loop
      dbms_session.set_context(c_namespace, c_prefix_perm || p.permission_name, 'Y');
    end loop;

    -- 4. ESTABLISHED goes last, deliberately. If loading raised part-way through, this is never
    --    set, so is_authenticated stays false and a half-populated context cannot be mistaken for
    --    a complete one.
    dbms_session.set_context(c_namespace, c_attr_established, 'Y');

    return true;
  exception
    when others then
      -- Any unexpected failure denies and leaves nothing behind. Fail closed, per rule 3.
      begin
        dbms_session.clear_all_context(c_namespace);
      exception
        when others then
          null;
      end;
      return false;
  end begin_request;

  -- NVL is load-bearing, not decoration. SYS_CONTEXT returns NULL for an attribute that was never
  -- set, and NULL = 'Y' evaluates to NULL rather than FALSE. A NULL returned from here would make
  -- "if not is_authenticated then return false" fail to fire, and "if not has_permission then
  -- raise" fail to raise -- so an unheld permission would pass silently. Rule 3 requires false,
  -- never null. Caught by test_pooled_session_does_not_bleed, which asserted FALSE and got NULL.
  function is_authenticated return boolean is
  begin
    return nvl(sys_context(c_namespace, c_attr_established), 'N') = 'Y';
  end is_authenticated;

  function principal_id return number is
  begin
    if not is_authenticated then
      return null;
    end if;
    return to_number(sys_context(c_namespace, c_attr_principal_id));
  end principal_id;

  function subject return varchar2 is
  begin
    if not is_authenticated then
      return null;
    end if;
    return sys_context(c_namespace, c_attr_subject, c_len_subject);
  end subject;

  function issuer return varchar2 is
  begin
    if not is_authenticated then
      return null;
    end if;
    return sys_context(c_namespace, c_attr_issuer, c_len_issuer);
  end issuer;

  function has_role(p_role_name in varchar2) return boolean is
  begin
    -- The is_authenticated gate is what makes an unestablished context return false rather than
    -- null-tolerant nonsense (section 6.3). Never true, never null.
    if not is_authenticated or p_role_name is null then
      return false;
    end if;
    return nvl(sys_context(c_namespace, c_prefix_role || p_role_name), 'N') = 'Y';
  end has_role;

  function has_permission(p_permission_name in varchar2) return boolean is
  begin
    if not is_authenticated or p_permission_name is null then
      return false;
    end if;
    return nvl(sys_context(c_namespace, c_prefix_perm || p_permission_name), 'N') = 'Y';
  end has_permission;

  procedure require_role(p_role_name in varchar2) is
  begin
    if not has_role(p_role_name) then
      raise_application_error(c_forbidden, 'Role required: ' || p_role_name);
    end if;
  end require_role;

  procedure require_permission(p_permission_name in varchar2) is
  begin
    if not has_permission(p_permission_name) then
      raise_application_error(c_forbidden, 'Permission required: ' || p_permission_name);
    end if;
  end require_permission;

end road_ctx_pkg;
/
