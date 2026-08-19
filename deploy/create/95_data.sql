whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy seed data ===

-- Autonomous Database enables parallel DML by default. Every insert below both reads and writes the
-- table it targets (the NOT EXISTS guard), and once any serial DML has happened in the transaction a
-- subsequent parallel one raises ORA-12839. Parallelism is worthless for a dozen seed rows, so turn
-- it off explicitly rather than relying on the optimizer staying serial -- which is what silently
-- held for the single-row inserts and broke on the first multi-row one.
alter session disable parallel dml;

prompt --- road_config ---

-- Every insert here is guarded by a NOT EXISTS rather than a MERGE, because this script runs on
-- every deploy and must not silently undo an operator's changes (build plan 1.2). A row that
-- already exists is left exactly as the operator left it, including a renamed default role.

insert into road_config (config_key, config_value, description)
select 'default_principal_role',
       'user',
       'Role granted to a principal created by invitation or auto-provisioning. Names an '
       || 'unreserved role, so an application may point this at a role of its own.'
  from dual
 where not exists (select 1 from road_config where config_key = 'default_principal_role');

insert into road_config (config_key, config_value, description)
select 'bootstrap_admin_subject',
       'ADMIN',
       'Subject of the principal that receives road.system_admin on a fresh deployment. The '
       || 'matching issuer is not configured here -- it is read from the schema JWT profile, so it '
       || 'is correct per environment automatically. See spec-patch-06 section 10 question 1.'
  from dual
 where not exists (select 1 from road_config where config_key = 'bootstrap_admin_subject');

-- Defaults to N in road-kit, unlike road-cal which sets Y. Rule 3 is fail closed, and a framework
-- must not decide on a deployer's behalf that their issuer may create accounts in their
-- application. An adopter that wants first-authentication provisioning turns it on deliberately --
-- which is a one-row change, and a decision someone made rather than inherited.
insert into road_config (config_key, config_value, description)
select 'auto_provision_principals',
       'N',
       'Y creates a principal on first authentication, granting default_principal_role. N denies '
       || 'an unknown subject, which is rule 3''s fail-closed default. This is a posture decision '
       || 'per deployment -- whether the issuer is trusted to decide who exists -- not a mechanism.'
  from dual
 where not exists (select 1 from road_config where config_key = 'auto_provision_principals');

prompt --- road_roles ---

insert into road_roles (role_name, display_name, description, is_reserved)
select 'road.system_admin',
       'System Administrator',
       'Defines roles and permissions, and grants anything. Holds no application permissions by '
       || 'default -- rule 2 forbids hierarchy, so this role is not implicitly privileged in an '
       || 'application.',
       'Y'
  from dual
 where not exists (select 1 from road_roles where role_name = 'road.system_admin');

insert into road_roles (role_name, display_name, description, is_reserved)
select 'road.user_admin',
       'User Administrator',
       'Grants and revokes roles. Cannot invent them, and cannot grant road.system_admin -- that '
       || 'separation is the entire point of the two-tier split.',
       'Y'
  from dual
 where not exists (select 1 from road_roles where role_name = 'road.user_admin');

insert into road_roles (role_name, display_name, description, is_reserved)
select 'user',
       'User',
       'Default role for a new principal. Deliberately unreserved: it gates nothing the framework '
       || 'enforces, so an application may rename, redefine or delete it.',
       'N'
  from dual
 where not exists (select 1 from road_roles where role_name = 'user');

prompt --- road_permissions ---

-- is_reserved is baked into these inserts for a fresh deploy. An already-deployed schema's
-- existing rows are NOT touched by insert (the NOT EXISTS guard skips them), which is why the
-- "mark reserved" UPDATE below exists as a separate, explicit migration step
-- (spec-patch-07 section 4.1) -- ALTER TABLE ... ADD defaults every row to 'N', including these.
--
-- Every permission road-kit ships is reserved, because every one of them is the framework's own
-- authority. An adopting application's permissions are the unreserved ones, and road-kit has none
-- of its own -- see planning/spec-patch-08-road-kit-demo-app.md (in road-cal) for the demo app
-- that gives the framework something unreserved to test against.
insert into road_permissions (permission_name, description, is_reserved)
select 'road.role.define', 'Create and modify role definitions.', 'Y'
  from dual
 where not exists (select 1 from road_permissions where permission_name = 'road.role.define');

insert into road_permissions (permission_name, description, is_reserved)
select 'road.permission.define',
       'Create and modify permission definitions. Deploy-time only -- checked by nothing at '
       || 'runtime (spec-patch-07 section 6). Creating a permission is a release-time act; only '
       || 'composing an existing one onto a role is runtime data.',
       'Y'
  from dual
 where not exists (select 1 from road_permissions where permission_name = 'road.permission.define');

insert into road_permissions (permission_name, description, is_reserved)
select 'road.role.grant', 'Grant a role to a principal.', 'Y'
  from dual
 where not exists (select 1 from road_permissions where permission_name = 'road.role.grant');

insert into road_permissions (permission_name, description, is_reserved)
select 'road.role.revoke', 'Revoke a role from a principal.', 'Y'
  from dual
 where not exists (select 1 from road_permissions where permission_name = 'road.role.revoke');

insert into road_permissions (permission_name, description, is_reserved)
select 'road.role.compose',
       'Attach or detach an existing permission on an existing role. Not road.user_admin -- that '
       || 'role administers people, not what a role means (spec-patch-07 section 6).',
       'Y'
  from dual
 where not exists (select 1 from road_permissions where permission_name = 'road.role.compose');

prompt --- mark existing permissions reserved (patch 07 migration) ---

-- Fixes up a schema that already had these rows before is_reserved existed -- the insert guards
-- above only fire on a genuinely fresh row. Idempotent and safe to run on a fresh deploy too
-- (matches what the inserts above already wrote). Must run before deploy/create/96_assertions.sql
-- creates the composition guard, and before any handler that can call attach_permission is
-- deployed -- otherwise these rows sit composable during the gap (spec-patch-07 section 4.1).
update road_permissions
   set is_reserved = 'Y'
 where permission_name in (
         'road.role.define', 'road.permission.define', 'road.role.grant', 'road.role.revoke',
         'road.role.compose'
       )
   and is_reserved = 'N';

prompt --- road_role_permissions ---

-- Explicit rows, never a wildcard: a permission added later must not be silently acquired by an
-- existing role (rule 4). Written one row per statement rather than as a set-based insert -- it
-- reads as exactly what it is, a fixed list of deliberate grants, and each line is greppable.
insert into road_role_permissions (role_name, permission_name)
select 'road.system_admin', 'road.role.define' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.system_admin' and permission_name = 'road.role.define');

insert into road_role_permissions (role_name, permission_name)
select 'road.system_admin', 'road.permission.define' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.system_admin' and permission_name = 'road.permission.define');

insert into road_role_permissions (role_name, permission_name)
select 'road.system_admin', 'road.role.grant' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.system_admin' and permission_name = 'road.role.grant');

insert into road_role_permissions (role_name, permission_name)
select 'road.system_admin', 'road.role.revoke' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.system_admin' and permission_name = 'road.role.revoke');

-- road.role.compose is road.system_admin's alone, deliberately NOT road.user_admin's: that role
-- administers people, not what a role means (spec-patch-07 section 6). attached_by is left to
-- default NULL -- "seeded at deploy time" -- which is what road_reserved_composition reads to
-- permit a reserved permission here while refusing the same attach from a session.
insert into road_role_permissions (role_name, permission_name)
select 'road.system_admin', 'road.role.compose' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.system_admin' and permission_name = 'road.role.compose');

-- road.user_admin grants and revokes, but deliberately cannot define. Nothing in the table
-- structure enforces that separation, so it lives here and is asserted in 99_verify.
insert into road_role_permissions (role_name, permission_name)
select 'road.user_admin', 'road.role.grant' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.user_admin' and permission_name = 'road.role.grant');

insert into road_role_permissions (role_name, permission_name)
select 'road.user_admin', 'road.role.revoke' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'road.user_admin' and permission_name = 'road.role.revoke');

prompt --- bootstrap administrator ---

-- Phase 0.2 decision: road.system_admin is seeded from deploy configuration, not handed to whoever
-- authenticates first. Break-glass on first login is a race, and on an internet-facing dev host
-- whoever wins it owns the system.
--
-- The issuer is read from the schema's own JWT profile rather than configured separately. ORDS
-- validates a token's iss against that profile before admitting the request, so the profile issuer
-- is by construction the issuer any real caller will present -- which is what makes the seeded
-- principal actually matchable at login. See planning/spike-06-1-iss-reachability.md.
declare
  l_issuer       varchar2(512 char);
  l_subject      road_config.config_value%type;
  l_principal_id road_principals.principal_id%type;
  l_admin_count  number;
  l_profiles     number;
  l_default_role road_config.config_value%type;
begin
  select count(*) into l_profiles from user_ords_jwt_profile;

  if l_profiles != 1 then
    -- Fail loudly rather than seeding a principal against a guessed issuer. 99_verify asserts this
    -- too; the deploy should not reach a state where identity exists but nobody can administer it.
    dbms_output.put_line(
      '[WARN] Expected exactly one ORDS JWT profile, found ' || l_profiles
      || ' - bootstrap administrator NOT seeded'
    );
    return;
  end if;

  select issuer into l_issuer from user_ords_jwt_profile;

  select config_value
    into l_subject
    from road_config
   where config_key = 'bootstrap_admin_subject';

  if l_subject is null then
    dbms_output.put_line('[WARN] road_config.bootstrap_admin_subject is empty - bootstrap administrator NOT seeded');
    return;
  end if;

  -- Ensure the principal exists. Matched on (issuer, subject), which is the real key.
  begin
    select principal_id
      into l_principal_id
      from road_principals
     where issuer = l_issuer
       and subject = l_subject;
  exception
    when no_data_found then
      insert into road_principals (issuer, subject, display_name)
      values (l_issuer, l_subject, 'Bootstrap Administrator')
      returning principal_id into l_principal_id;

      dbms_output.put_line('[INFO] Created bootstrap principal ' || l_principal_id
                           || ' for ' || l_issuer || ' / ' || l_subject);
  end;

  -- Grant road.system_admin only when nobody holds it at all. This makes a re-deploy a rescue for a
  -- deployment with zero administrators, without ever fighting an operator who deliberately revoked
  -- this particular principal while others remain. It is not break-glass: the identity is fixed by
  -- configuration in advance, so there is no race and no first-come-first-served.
  select count(*)
    into l_admin_count
    from road_principal_roles
   where role_name = 'road.system_admin';

  if l_admin_count = 0 then
    insert into road_principal_roles (principal_id, role_name)
    values (l_principal_id, 'road.system_admin');

    dbms_output.put_line('[INFO] Granted road.system_admin to principal ' || l_principal_id);
  else
    dbms_output.put_line('[INFO] ' || l_admin_count
                         || ' principal(s) already hold road.system_admin - no grant made');
  end if;

  -- The administrator also needs the ordinary application role. road.system_admin grants the four
  -- road.* permissions and NOTHING else -- rule 2 forbids hierarchy, so it does not inherit
  -- application permissions and never should. Without this the bootstrap admin can administer roles
  -- and cannot read its own session, which is exactly what happened the first time phase 6 ran.
  --
  -- Being an administrator is additional to being a user, not instead of it.
  select config_value into l_default_role
    from road_config where config_key = 'default_principal_role';

  if l_default_role is not null then
    insert into road_principal_roles (principal_id, role_name)
    select l_principal_id, l_default_role from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_principal_id and role_name = l_default_role)
       and exists (select 1 from road_roles where role_name = l_default_role);
  end if;
end;
/

commit;

prompt --- application permission grants ---

-- road-kit ships NO application permissions, so there is nothing to grant here. An adopting
-- application inserts its own operation names into road_permissions and decides which roles hold
-- them.
--
-- road_admin_api.grant_all_app_permissions('user') is available as a deploy-time convenience for a
-- new application, writing explicit rows. It is correct only until the application has its first
-- admin-only permission, at which point the blanket grant would hand that power to every user and
-- grants must become explicit. road-cal demonstrates exactly that graduation -- see its own
-- 95_data.sql, where the call was removed when events.purge arrived.

prompt --- seeded state ---

select role_name, is_reserved from road_roles order by role_name;
select role_name, permission_name from road_role_permissions order by role_name, permission_name;
select config_key, config_value from road_config order by config_key;
