whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Drop the framework package specifications (and, by dependency, their bodies).
-- Approach: Explicit drop statements guarded so a missing object is not an error.
-- Reason: Part of the full teardown; also used to force a clean recompile.
-- Expected objects: REMOVED - UI_ASSETS_API, HEALTH_API, JWT_SCAFFOLD_AUTH_API, SESSION_API
-- Risk: Medium. No data loss, but the API is non-functional until the create chain reruns.
-- Prior history checked: Not usually needed - safe to rerun.
-- END INTENT

prompt === drop package specs ===
begin
  execute immediate 'drop package road_audit_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package road_audit_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package road_admin_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package road_admin_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package road_ctx_pkg_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package road_ctx_pkg';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package error_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package error_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package ui_assets_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop package health_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop package jwt_scaffold_auth_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop package session_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
