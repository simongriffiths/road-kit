create or replace package road_ctx_pkg as

  -- Session identity and authorisation for ROAD applications (spec-patch-06 section 6).
  --
  -- The ROAD_CTX application context is created WITH THIS PACKAGE as its trusted setter
  -- (`create or replace context road_ctx using road_ctx_pkg`). That USING clause is the security
  -- control, not decoration: no other code in the schema can write identity into the context, so a
  -- handler cannot promote itself by calling dbms_session.set_context directly.
  --
  -- Usage at the top of a protected handler:
  --
  --   if not road_ctx_pkg.begin_request(:current_user) then
  --     :status_code := 401;
  --     return;
  --   end if;
  --   road_ctx_pkg.require_permission('events.create');
  --
  -- ORDS does not fire a schema-level pre-hook -- there is no registration API reachable from the
  -- schema -- so begin_request is called per handler. Everything here therefore fails closed: an
  -- unestablished context grants nothing, never everything.

  -- The application context namespace this schema uses.
  --
  -- Application contexts are DATABASE-GLOBAL, not schema-scoped: `create or replace context road_ctx
  -- using road_ctx_pkg` run from a second schema silently re-points the one shared namespace at that
  -- schema's package, and the first schema then gets ORA-01031 from dbms_session on every request.
  -- Found the hard way when the road-kit backport was deployed to the same ADB as road-cal.
  --
  -- Deriving it from the current schema makes two ROAD applications on one database independent.
  -- The deploy script creates a context with exactly this name.
  function namespace return varchar2;

  -- Raised by require_permission and require_role when an AUTHENTICATED principal lacks the
  -- requirement. Mapped by error_api to HTTP 403. The number is mnemonic: -20403 -> 403.
  -- A caller who is not authenticated at all is ORDS's 401 and never reaches here.
  c_forbidden constant number := -20403;

  -- Establishes session identity for one request. Resolves (issuer, subject) to a principal,
  -- requires status ACTIVE, and loads that principal's effective permissions into the context in
  -- one pass. Returns false -- never raises -- on any failure, including an unknown subject, a
  -- suspended principal, or an unresolvable issuer.
  --
  -- p_issuer defaults to null, in which case the issuer is read from the schema's own ORDS JWT
  -- profile. ORDS validates a token's iss against that profile before admitting the request, so the
  -- profile issuer is by construction the issuer the caller presented.
  --
  -- ALWAYS clears any existing context first. ORDS pools connections, so this session may still
  -- hold the previous caller's identity.
  function begin_request(
    p_subject in varchar2,
    p_issuer  in varchar2 default null
  ) return boolean;

  -- Clears all session identity. Safe to call when nothing was established.
  procedure end_request;

  function principal_id return number;
  function subject      return varchar2;
  function issuer       return varchar2;

  -- True only after a successful begin_request on this session.
  function is_authenticated return boolean;

  -- Coarse check, kept so a simple application can ignore permissions entirely. Permissions are
  -- what the framework teaches, because they make role composition a data change (section 6.1).
  function has_role(p_role_name in varchar2) return boolean;

  -- Reads the context, never the tables -- one query per request, not one per check.
  function has_permission(p_permission_name in varchar2) return boolean;

  -- Raise c_forbidden unless held.
  procedure require_role(p_role_name in varchar2);
  procedure require_permission(p_permission_name in varchar2);

end road_ctx_pkg;
/
