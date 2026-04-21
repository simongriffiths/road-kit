set define on
set verify off
set feedback on

prompt
prompt === ROAD Create Schema User ===
prompt This script is intended to be run manually by an admin-capable user.
prompt It is separate from normal application deployment.
prompt

accept schema_user char prompt 'Schema user: '
accept schema_password char prompt 'Schema password: ' hide
accept default_tablespace char default 'DATA' prompt 'Default tablespace [DATA]: '
accept temporary_tablespace char default 'TEMP' prompt 'Temporary tablespace [TEMP]: '
accept quota_mb char default '500' prompt 'Quota in MB on default tablespace [500]: '

declare
  l_exists number;
begin
  select count(*)
    into l_exists
    from dba_users
   where username = upper('&&schema_user');

  if l_exists > 0 then
    raise_application_error(-20000, 'User already exists: ' || upper('&&schema_user'));
  end if;
end;
/

create user &&schema_user
  identified by "&&schema_password"
  default tablespace &&default_tablespace
  temporary tablespace &&temporary_tablespace
  quota &&quota_mb.M on &&default_tablespace
  account unlock;

prompt
prompt User created:
prompt   &&schema_user
prompt

undefine schema_user
undefine schema_password
undefine default_tablespace
undefine temporary_tablespace
undefine quota_mb
