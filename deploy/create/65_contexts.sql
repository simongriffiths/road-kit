whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy application contexts ===

-- The USING clause is the security control, not decoration: it names the only package permitted to
-- write this namespace, so application code cannot set its own identity by calling
-- dbms_session.set_context directly (spec-patch-06 section 6.2).
--
-- The namespace is DERIVED FROM THE SCHEMA, not fixed, because application contexts are
-- database-global objects. A fixed 'ROAD_CTX' means the second ROAD application deployed to a
-- database silently re-points the namespace at its own package, and the first one then gets
-- ORA-01031 from dbms_session on every request -- with nothing in its own repo having changed.
-- Confirmed on this ADB: deploying road-kit broke road-cal, and re-deploying road-cal broke
-- road-kit. road_ctx_pkg.namespace derives the same value at runtime.
--
-- Requires CREATE ANY CONTEXT; the drop script additionally requires DROP ANY CONTEXT. Oracle has
-- no schema-scoped equivalent of either.
declare
  l_namespace varchar2(30) := substr('ROAD_CTX_' || sys_context('USERENV', 'CURRENT_SCHEMA'), 1, 30);
begin
  execute immediate 'create or replace context ' || l_namespace || ' using road_ctx_pkg';
  dbms_output.put_line('[INFO] Context ' || l_namespace || ' created for road_ctx_pkg');
end;
/

-- Remove the pre-namespacing context if this schema still has one. Harmless when absent, and
-- leaving it would keep a globally-shared namespace alive that another schema could re-point.
begin
  execute immediate 'drop context road_ctx';
exception
  when others then
    if sqlcode not in (-4043, -1031, -41726) then
      raise;
    end if;
end;
/
