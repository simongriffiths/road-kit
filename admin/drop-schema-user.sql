set define on
set verify off
set feedback on

prompt
prompt === ROAD Drop Schema User ===
prompt This script is intended to be run manually by an admin-capable user.
prompt Use with care. The schema is dropped with CASCADE.
prompt

accept schema_user char prompt 'Schema user to drop: '

declare
  l_exists number;
begin
  select count(*)
    into l_exists
    from dba_users
   where username = upper('&&schema_user');

  if l_exists = 0 then
    raise_application_error(-20001, 'User does not exist: ' || upper('&&schema_user'));
  end if;
end;
/

drop user &&schema_user cascade;

prompt
prompt User dropped:
prompt   &&schema_user
prompt

undefine schema_user
