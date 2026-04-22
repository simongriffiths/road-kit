whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop package specs ===
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
