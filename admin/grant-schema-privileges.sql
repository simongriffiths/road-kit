whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

set define on
set verify off
set feedback on

prompt
prompt === ROAD Grant Schema Privileges ===
prompt This script may be run against an already-existing schema owner.
prompt It grants the minimum baseline privileges and quota needed for ROAD object deployment.
prompt

accept schema_user char prompt 'Existing schema user: '
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

  if l_exists = 0 then
    raise_application_error(-20002, 'User does not exist: ' || upper('&&schema_user'));
  end if;
end;
/

alter user &&schema_user
  default tablespace &&default_tablespace
  temporary tablespace &&temporary_tablespace
  quota &&quota_mb.M on &&default_tablespace
  account unlock;

grant create session to &&schema_user;
grant create table to &&schema_user;
grant create view to &&schema_user;
grant create sequence to &&schema_user;
grant create procedure to &&schema_user;
grant create type to &&schema_user;
grant create trigger to &&schema_user;
grant create synonym to &&schema_user;

-- Required by spec patch 06: the road_ctx application context is created with
--   create or replace context road_ctx using road_ctx_pkg;
-- Oracle has no schema-scoped equivalent -- context creation requires CREATE ANY CONTEXT, which is
-- broader than the grants above and can also alter or drop contexts owned by other schemas. Granted
-- because road_ctx is framework baseline for every ROAD application, not app-specific.
grant create any context to &&schema_user;

grant execute on dbms_crypto to &&schema_user;
grant execute on utl_encode to &&schema_user;
grant execute on utl_i18n to &&schema_user;

prompt
prompt Grants applied to:
prompt   &&schema_user
prompt
prompt Baseline ROAD schema-owner privileges granted:
prompt   CREATE SESSION
prompt   CREATE TABLE
prompt   CREATE VIEW
prompt   CREATE SEQUENCE
prompt   CREATE PROCEDURE
prompt   CREATE TYPE
prompt   CREATE TRIGGER
prompt   CREATE SYNONYM
prompt   CREATE ANY CONTEXT
prompt   EXECUTE ON DBMS_CRYPTO
prompt   EXECUTE ON UTL_ENCODE
prompt   EXECUTE ON UTL_I18N
prompt

undefine schema_user
undefine default_tablespace
undefine temporary_tablespace
undefine quota_mb

exit success
