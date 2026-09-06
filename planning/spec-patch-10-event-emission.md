# Specification Patch 10 — After-Commit Event Emission

**Applies to:** new framework capability. No existing spec section owns this; once built it
becomes its own entry in `spec/framework-spec-index-v1.md` §3.
**Status:** design, 2026-09-04. Not built.
**Canonical location.** Framework work, built in road-kit.

**Related:**
`planning/governed-state-contracts-proof-plan-v1.md` — why this exists at all (W3).
`planning/spec-patch-11-governed-completion-action.md` — the first caller. Depends on this
patch being built and deployed first.

---

## 1. What this is

A generic **transactional outbox**. A governed action's decision path writes an event row in
the *same* transaction as its state change and its audit row. Any other session sees that row
only once the transaction commits — ordinary read-committed visibility, not a new coordination
mechanism.

That is the entire trick, and it is what makes `after_commit` a property the code *has* rather
than a claim the documentation *makes*: a decision that rolls back takes its event with it, so
nothing downstream can ever be told about something that did not happen.

### 1.1 Why the framework needs it

`spec/governed-state-contract.schema.json` (`v0.1.0`, tag `v0.1.0`) requires every contract to
declare `events.emitted[].when: "after_commit"`. Nothing in road-kit emits an event of any
kind — confirmed 2026-09-04, no queue, outbox, notification or dispatch mechanism anywhere in
the repository.

It is raised as its own patch because `demo_todo_api`'s constitution requires it:

> THE DEMO APP MAY NEVER CAUSE A FRAMEWORK CHANGE. If it needs something road-kit lacks, that
> is a specification question for the framework, raised separately — never a change smuggled
> in under a demo.

Patch 11 is the demo-domain work that consumes this. Keeping them separate keeps that boundary
legible: **this** patch changes what every adopter deploys; patch 11 changes only what road-kit
exercises on itself.

## 2. Table

```sql
create table road_events (
  event_id      number generated always as identity,
  event_name    varchar2(200 char) not null,
  capability_id varchar2(200 char),
  payload       json,
  occurred_at   timestamp with time zone default systimestamp not null,
  status        varchar2(10 char) default 'PENDING' not null,
  dispatched_at timestamp with time zone,
  constraint road_events_pk primary key (event_id),
  constraint road_events_status_ck check (status in ('PENDING', 'DISPATCHED', 'FAILED'))
);

create index road_events_status on road_events (status, occurred_at);
```

`capability_id` is deliberately free text with no foreign key. There is no contract registry
table — contracts are JSON documents in `spec/` — so a key would point at nothing. It exists so
"which governed action produced this event" is answerable without parsing `payload`.

`payload` carries whatever the emitting action needs its consumer to know. For patch 11 that is
the completed todo and the principals who should be notified. It is deliberately unconstrained
here: the framework does not know what any given business action's event means, and a schema
imposed at this layer would be guessing.

**`status` and `dispatched_at` ship even though nothing sets them in this patch.** The outbox
shape is the point — a table without them is a log, and retrofitting a status column onto a
framework table that adopters have already deployed is exactly the migration road-kit should
not need to perform. See §5.

## 3. Package

```sql
create or replace package road_event_api as

  -- Records an event in the CALLER's current transaction. NOT autonomous -- deliberately the
  -- opposite of road_audit_api.log_admin_action, and the reason is the whole point of this
  -- package: the row is durable, and visible to any other session, only once the caller
  -- commits. A caller that rolls back takes the event with it.
  --
  -- Returns the event_id so the emitting action's own audit row can reference it. A decision
  -- and the effect it authorised are then linked in the record rather than merely adjacent in
  -- time.
  function emit(
    p_event_name    in varchar2,
    p_capability_id in varchar2 default null,
    p_payload       in json default null
  ) return number;

  -- Up to p_limit PENDING events, oldest first, as a JSON array. Read-only: claiming is a
  -- separate decision, so a reader that dies mid-handling has changed nothing.
  function get_pending(p_limit in number default 50) return json;

  -- Marks one event DISPATCHED or FAILED. AUTONOMOUS, and this asymmetry with emit is
  -- deliberate: the emit must stand or fall with the decision that caused it, whereas the
  -- record that a hand-off was attempted must survive whatever the handler does next -- the
  -- same reasoning road_audit_api.log_admin_action applies, on the opposite side of the row's
  -- life.
  procedure mark_dispatched(
    p_event_id in number,
    p_status   in varchar2 default 'DISPATCHED'
  );

end road_event_api;
/
```

## 4. Why this is not part of `road_audit_api`

`road_audit_api.log_admin_action` is autonomous by design, so an attempted-and-failed action
still leaves a record — "an action that was attempted and failed is exactly the one worth having
a record of."

`emit` needs the opposite guarantee. If it were autonomous, a rejected-and-rolled-back proposal
would still announce `todo.completed` to everything downstream. Two different correctness
properties; putting them in one package would make one of them silently wrong depending on which
entry point a reader happened to be looking at.

**Consequence for patch 11:** the governed action's own audit write — the schema's
`audit.transactional: true` — must not go through `log_admin_action` either, for the same
reason. That is patch 11's problem to solve, not this one's.

## 5. What this patch deliberately does not build

**A dispatcher.** Nothing here delivers an event anywhere — no email, no webhook, no AQ.

The reason is not "there is no consumer": patch 11 supplies one, in that `todo.completed`
carries the contributors who should be told. The reason is that **delivery proves nothing about
governance.** Standing up an outbound mail path is real infrastructure — sender domain, OCI
Email Delivery approval and sandbox limits, an ACL for outbound calls, credential handling — and
none of it makes the "consumers propose, the authority decides" claim any more or less true.
Every stage of this proof plan so far has been deliberately dependency-free, and this is the
first place that could quietly stop being true.

The event carries its recipient list. Delivery is a conventional integration, deferred until
something actually needs to receive one.

`mark_dispatched` ships anyway, unused, so that whoever writes that dispatcher does not have to
reopen a framework package to do it.

## 6. Deploy wiring

Framework placement, mirroring `road_audit_api` exactly:

| Artefact | Registered in |
|---|---|
| `db/tables/road_events.create.sql` / `.drop.sql` | `deploy/create/10_tables.sql` |
| the index | `deploy/create/20_indexes.sql` |
| `db/package_specs/road_event_api.pks` | `deploy/create/60_package_specs.sql` |
| `db/package_bodies/road_event_api.pkb` | `deploy/create/70_package_bodies.sql` |
| `road_event_api_test` spec + body | alongside, as `road_audit_api_test` is |

Part of `00_full.sql`. Every adopter gets it; it is not gated behind `97_demo.sql`.

Table create/drop scripts must be ORA-955-tolerant, per road-atlas `F-10` and the pattern in
`db/tables/demo_todos.create.sql`.

## 7. Test plan

`road_event_api_test`, matching `road_audit_api_test`'s structure. Tests roll back to a
savepoint; the package never commits.

1. `emit` then commit → row present, `status = 'PENDING'`, `occurred_at` set, returned
   `event_id` matches the row.
2. **`emit` then rollback → no row.** This is the assertion that proves `after_commit` rather
   than naming it, and it is the one to quote.
3. `get_pending` returns oldest-first, honours `p_limit`, excludes non-`PENDING` rows.
4. `mark_dispatched` sets `status` and `dispatched_at`, and touches no other row.
5. `mark_dispatched(p_status => 'FAILED')` sets `FAILED`.
6. `mark_dispatched` survives the emitting transaction having already committed — the normal
   case, stated explicitly because its autonomy is what makes it true.
7. `emit` with a null `p_payload` and null `p_capability_id` succeeds — both are optional, and a
   framework primitive that only works fully-populated is a trap for the first adopter.

## 8. Out of scope

- Any dispatcher or outbound delivery (§5).
- Retention or purge of `road_events`. A framework table needs a policy eventually; bundling one
  into this patch would smuggle in a second decision.
- Ordering or delivery guarantees beyond "not visible before commit." No exactly-once claim is
  made and none should be quoted.
- Any change to `road_audit_api`.
- Patch 11's governed action, contributors table, or assertion.

## 9. Provenance

Read 2026-09-04: `db/package_specs/road_audit_api.pks`, `db/package_specs/demo_todo_api.pks`
(Rule 1, error-code constants), `db/package_bodies/error_api.pkb` (fixed status mapping),
`deploy/create/97_demo.sql` (placement rationale), `deploy/create/96_assertions.sql`,
`db/tables/demo_todos.create.sql` (ORA-955 tolerance).
Confirmed by search, same date, that no event, outbox, queue or notification mechanism exists in
the repository, and that no dictionary object or spec section already claims `road_events` or
`road_event_api`.
