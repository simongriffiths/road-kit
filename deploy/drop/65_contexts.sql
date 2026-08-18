whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop application contexts ===

-- Needs DROP ANY CONTEXT, which is a SEPARATE privilege from CREATE ANY CONTEXT -- a schema that can
-- create a context cannot necessarily drop it, and ORA-41726 is easy to misread as "not there".
-- Tolerated so a teardown on a schema without the privilege still completes.
declare
  l_namespace varchar2(30) := substr('ROAD_CTX_' || sys_context('USERENV', 'CURRENT_SCHEMA'), 1, 30);
begin
  execute immediate 'drop context ' || l_namespace;
exception
  when others then
    if sqlcode not in (-4043, -1031, -41726) then
      raise;
    end if;
end;
/
