whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop package bodies ===
begin
  execute immediate 'drop package body road_audit_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body road_audit_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body road_admin_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body road_admin_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body road_ctx_pkg_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body road_ctx_pkg';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body error_api_test';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
begin
  execute immediate 'drop package body error_api';
exception
  when others then
    if sqlcode != -4043 then
      raise;
    end if;
end;
/
prompt health_api body is dropped with the package spec
