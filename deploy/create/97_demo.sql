whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === demo application (spec patch 08) ===

-- INTENT:
-- Purpose: Deploy the todo demo application -- one table, one package, its permissions and its
--   role -- so road-kit's own framework features can be exercised in road-kit.
-- Approach: Table, index and trigger, then the package, then the seed, then verification.
-- Reason: Three framework features are untestable without an application: the RESERVED
--   application permission (spec-patch-07 section 3.1's worked example),
--   grant_all_app_permissions, and the "an application extends the role model" pattern.
-- Expected objects: DEMO_TODOS, DEMO_TODOS_OWNER_STATUS, DEMO_TODOS_UPDATED_AT_TRG,
--   DEMO_TODO_API (+ _TEST), 7 permissions, 1 role.
-- Risk: Low, and confined -- every object is demo_/todo. prefixed.
-- Prior history checked: build-plan-08 phase 5.
-- END INTENT

-- NOT INVOKED BY deploy/create/00_full.sql, DELIBERATELY (spec-patch-08 section 3.1).
--
-- Two failure modes this placement avoids. In 00_full.sql, every adopter deploys todo tables and
-- then deletes them, and road-kit stops being clean to adopt -- which is the one thing it is for.
-- Kept fully separate and never run, the demo rots, and an unexercised demo is worse than none.
--
-- Resolution: this file is run unconditionally by whatever deploys road_kit_dev, and by nobody
-- else. Dev is the exercise environment; adopters get the framework alone.
--
-- 97_, after 96_assertions.sql, is also deliberate: this seeds a RESERVED permission, so the
-- assertions must already exist to validate that seed rather than be validated by it.

prompt --- table, index, trigger ---

@db/tables/demo_todos.create.sql
@db/triggers/demo_todos_updated_at.create.sql

prompt --- package ---

@db/package_specs/demo_todo_api.pks
@db/package_specs/demo_todo_api_test.pks
@db/package_bodies/demo_todo_api.pkb
@db/package_bodies/demo_todo_api_test.pkb

prompt --- permissions ---

-- Six unreserved, one reserved. todo.purge is the reason this app exists: it is a RESERVED
-- APPLICATION permission that does not start with road., which is exactly the case
-- spec-patch-07 section 3.1 says a naming convention gets wrong. Until this file, road-kit had no
-- way to test that rule at all.
insert into road_permissions (permission_name, description, is_reserved)
select p.name, p.descr, p.reserved from (
  select 'todo.list'     as name, 'List your own todos'                 as descr, 'N' as reserved from dual union all
  select 'todo.get',           'Read one todo',                              'N' from dual union all
  select 'todo.create',        'Create a todo',                              'N' from dual union all
  select 'todo.update',        'Modify a todo you own',                      'N' from dual union all
  select 'todo.delete',        'Soft-delete a todo you own',                 'N' from dual union all
  select 'todo.list_all',      'List todos belonging to any principal',      'N' from dual union all
  select 'todo.purge',         'Irreversibly delete completed todos before a cutoff, across all '
                               || 'owners',                                  'Y' from dual
) p
 where not exists (select 1 from road_permissions x where x.permission_name = p.name);

-- The migration case, same shape as the framework's own in 95_data.sql: an ALTER-added column
-- defaults every pre-existing row to 'N', and the insert guard above skips rows that already
-- exist. Without this a schema that had todo.purge before is_reserved existed sits fail-open.
update road_permissions
   set is_reserved = 'Y'
 where permission_name = 'todo.purge'
   and is_reserved = 'N';

prompt --- todo_admin role ---

-- An application role, mirroring road-cal's calendar_admin. is_reserved = 'N': the role is the
-- application's to compose, unlike the road.* roles. It holds todo.list_all and todo.purge and
-- NOTHING ELSE -- an administrator of todos is not thereby a user of them, the same separation
-- rule 2 of spec patch 06 applies to road.system_admin.
insert into road_roles (role_name, display_name, description, is_reserved)
select 'todo_admin', 'Todo administrator',
       'Reads every principal''s todos and may purge completed ones. Holds no ordinary todo '
       || 'permissions -- administering todos is not using them.', 'N'
  from dual
 where not exists (select 1 from road_roles where role_name = 'todo_admin');

-- COMMIT HERE, before anything is attached to the new role. Not tidiness -- required.
--
-- With road_reserved_composition and road_admin_reachable in place, inserting into
-- road_role_permissions re-evaluates both assertions, and doing so against a PARENT ROLE created
-- in the same uncommitted transaction raises ORA-12860 ("deadlock detected while waiting for a
-- sibling row lock"). Found on 2026-08-19: the five `user` grants below succeed because `user` is
-- long committed by the framework seed, and the todo_admin grants failed until this commit was
-- added -- single-row or set-based made no difference.
--
-- Anything that creates a role and composes it in one deploy script must commit between the two.
-- road-kit's own 95_data.sql has never hit this because 95_data runs before 96_assertions on a
-- fresh deploy, so no assertion exists while it seeds.
commit;

prompt --- role composition ---

-- Spelled out row by row rather than through grant_all_app_permissions. That helper is for the
-- simple case and this is not it: it would give todo_admin every unreserved todo.* permission,
-- which is the opposite of what the role means. (It would correctly skip todo.purge -- that is
-- the spec-patch-08 section 7.1 fix -- but skipping the reserved one is not enough to make a
-- blanket grant right here.)
--
-- attached_by is left to default NULL throughout: "seeded at deploy time", which is what
-- road_reserved_composition reads to permit todo.purge here while refusing the identical attach
-- from a session.
insert into road_role_permissions (role_name, permission_name)
select 'user', p.name from (
  select 'todo.list' as name from dual union all
  select 'todo.get'         from dual union all
  select 'todo.create'      from dual union all
  select 'todo.update'      from dual union all
  select 'todo.delete'      from dual
) p
 where not exists (select 1 from road_role_permissions x
                    where x.role_name = 'user' and x.permission_name = p.name);

-- One row per statement, matching how 95_data.sql seeds the framework's own grants. The set-based
-- form works equally well here -- what the ORA-12860 above actually needed was the commit, not
-- this shape -- but a fixed list of deliberate grants reads better one line at a time and each
-- line is greppable.
insert into road_role_permissions (role_name, permission_name)
select 'todo_admin', 'todo.list_all' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'todo_admin' and permission_name = 'todo.list_all');

insert into road_role_permissions (role_name, permission_name)
select 'todo_admin', 'todo.purge' from dual
 where not exists (select 1 from road_role_permissions
                    where role_name = 'todo_admin' and permission_name = 'todo.purge');

commit;

prompt --- verify the demo model ---

declare
  l_count number;

  procedure assert(p_condition in boolean, p_message in varchar2) is
  begin
    if not nvl(p_condition, false) then
      raise_application_error(-20000, p_message);
    end if;
  end assert;
begin
  -- 1. todo.purge is reserved. If this ever reads 'N', the composition UI can hand the most
  --    destructive operation in the app to any role.
  select count(*) into l_count
    from road_permissions
   where permission_name = 'todo.purge' and is_reserved = 'Y';
  assert(l_count = 1, 'todo.purge must exist and be reserved');

  -- 2. And it is held by todo_admin alone (spec-patch-08 section 8, assertion 3).
  select count(*) into l_count
    from road_role_permissions
   where permission_name = 'todo.purge';
  assert(l_count = 1, 'todo.purge must be held by exactly one role, found ' || l_count);

  select count(*) into l_count
    from road_role_permissions
   where permission_name = 'todo.purge' and role_name = 'todo_admin';
  assert(l_count = 1, 'todo.purge must be held by todo_admin');

  -- 3. todo_admin holds no ordinary todo permission. Administering todos is not using them.
  select count(*) into l_count
    from road_role_permissions
   where role_name = 'todo_admin'
     and permission_name in ('todo.list', 'todo.get', 'todo.create', 'todo.update', 'todo.delete');
  assert(l_count = 0, 'todo_admin must hold no ordinary todo permissions, found ' || l_count);

  -- 4. Every todo attachment is deploy-seeded. A non-null attached_by here would mean a session
  --    wrote it, and for todo.purge the assertion should have refused that outright.
  select count(*) into l_count
    from road_role_permissions
   where permission_name like 'todo.%' and attached_by is not null;
  assert(l_count = 0, 'todo permissions must be deploy-attached, found ' || l_count || ' session rows');

  dbms_output.put_line('[INFO] Demo application verified: 7 permissions (1 reserved), '
                       || 'todo_admin correctly restricted');
end;
/
