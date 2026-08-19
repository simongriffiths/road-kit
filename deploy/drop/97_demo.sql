whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop demo application (spec patch 08) ===

-- Runs BEFORE the framework teardown, for the same reason 96_assertions.sql does: these rows are
-- children of road_permissions and road_roles, and road_reserved_composition constrains the table
-- they live in.
--
-- Deleting the seed rows before dropping the table is not redundant. road_role_permissions and
-- road_permissions are FRAMEWORK tables -- dropping demo_todos leaves the demo's rows in them, and
-- an adopter who ran the demo once would carry todo.purge in their permission catalogue forever.

prompt --- seed rows ---

delete from road_role_permissions where permission_name like 'todo.%';
delete from road_role_permissions where role_name = 'todo_admin';
delete from road_principal_roles where role_name = 'todo_admin';
delete from road_permissions where permission_name like 'todo.%';
delete from road_roles where role_name = 'todo_admin';
commit;

prompt --- package ---

begin
  execute immediate 'drop package body demo_todo_api_test';
exception
  when others then
    if sqlcode != -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop package body demo_todo_api';
exception
  when others then
    if sqlcode != -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop package demo_todo_api_test';
exception
  when others then
    if sqlcode != -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop package demo_todo_api';
exception
  when others then
    if sqlcode != -4043 then raise; end if;
end;
/

prompt --- trigger and table ---

@db/triggers/demo_todos_updated_at.drop.sql
@db/tables/demo_todos.drop.sql
