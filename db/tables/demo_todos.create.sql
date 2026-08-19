-- The demo application's only table (spec-patch-08 section 4). Not framework: nothing in road-kit's
-- own surface references it, and deploy/create/00_full.sql does not create it -- only
-- deploy/create/97_demo.sql does, which adopters do not run.
--
-- The demo_ prefix is load-bearing. It makes a stray demo object visible in user_tables at a
-- glance, so "did the demo get deployed into an adopter's schema" is answerable by one query.
--
-- This is NOT a template to build on. An adopter copying the demo should copy the WIRING -- the
-- require_permission calls, the ownership filter, the read_token handling, the error routing --
-- and throw the domain away (spec-patch-08 section 11).
--
-- status DELETED is a soft delete. Hard deletion exists only behind demo_todo_api.purge, which is
-- the point: a reserved permission needs something genuinely irreversible to guard, or the
-- demonstration is theatre.
--
-- updated_at is trigger-maintained (coding-standards-v1.md section 5.5) and is exposed for display
-- only. It is NOT the concurrency mechanism -- the opaque read_token from road_audit_api is
-- (spec-patch-08 section 6.2). A client-supplied updated_at is rejected, never honoured.
create table demo_todos (
  todo_id            number generated always as identity,
  owner_principal_id number not null references road_principals,
  title              varchar2(200 char) not null,
  notes              varchar2(4000 char),
  due_at             timestamp with time zone,
  status             varchar2(10 char) default 'OPEN' not null,
  created_at         timestamp with time zone default systimestamp not null,
  updated_at         timestamp with time zone default systimestamp not null,
  constraint demo_todos_pk primary key (todo_id),
  constraint demo_todos_status_ck check (status in ('OPEN', 'DONE', 'DELETED'))
);

-- Every list query filters on both columns: the ownership scope and the status exclusion.
create index demo_todos_owner_status on demo_todos (owner_principal_id, status);
