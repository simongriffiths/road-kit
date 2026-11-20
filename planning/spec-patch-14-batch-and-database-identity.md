# Specification Patch 14 — The Database-User Identity Path (batches deferred)

**Applies to:** framework surface. `road_ctx_pkg`: `begin_database_request`,
`is_database_identity_allowed` and `c_database_issuer`.
**Status:** identity path built and tested on `ROAD_KIT_DEV`, 20 November 2026. Batches are deferred
(section 6).
**Decisions it implements:** road-atlas ledger B-02, the database-user identity path. It follows
sections 5.2, 5.6 and 6.9 of the Governed Surface Contract definition, version 0.1.0 (draft).
**History:** written 14 November 2026 as batches, references and the identity path together.
Reviewed with Simon on 20 November 2026 and split: see section 6.

---

## 1. What this is

An agent or batch process connects as its own database user. A definer's-rights wrapper maps that
session to a road principal. Identity is never a parameter.

This is road-planner's `plan_agent_api` mapping (its D15 and AG-10), moved into the framework.

## 2. Rulings this patch carries over (B-02, 20 and 23 October 2026)

- **Two ways in.** Agents run work as database users. End users run work as themselves through REST.
- **No borrowed identity.** No session adopts an end user's security context. A process with no end
  user runs as its system owner, a database user.

## 3. The function

In `road_ctx_pkg`:

```sql
c_database_issuer constant varchar2(20) := 'urn:oracle-db';

function is_database_identity_allowed(p_database_user in varchar2) return boolean;
function begin_database_request return boolean;
```

`begin_database_request` reads `SESSION_USER`, the user that logged in, which a definer's-rights
wrapper cannot change, so the mapping cannot be forged. It then calls the same internal
establishing code as `begin_request`, with issuer `urn:oracle-db` and the database user name as
subject.

It returns false, and never raises, when:

- the user is refused by `is_database_identity_allowed`: null, `ORDS_PUBLIC_USER`, or the schema
  owner. These are the two identities a REST call runs as, so the REST path can never reach a
  database-user identity;
- no principal exists for that user, or its status is not ACTIVE.

**It never creates a principal**, whatever `road_config.auto_provision_principals` says. A database
user becomes a principal only when an administrator adds it. Auto-provisioning is for people an
identity provider has authenticated, and an unknown database login is not that. This is the one
difference from `begin_request`, which is otherwise the same code.

Like `begin_request`, it clears any existing context first, including on refusal.

A system process with no end user runs as its system owner (definition 5.2.4). Its database user
gets a principal like any other, with the roles the process needs.

## 4. The application's wrapper

Each application writes one definer's-rights wrapper package per database-user surface. road-kit
ships the pattern, not a generic wrapper, because the wrapper's functions are the application's
actions:

```sql
create or replace package item_agent_api as   -- definer's rights, the default
  function claim_item(p_request in json) return json;
end;

function claim_item(p_request in json) return json is
  l_outcome json;
begin
  if not road_ctx_pkg.begin_database_request then
    raise_application_error(road_ctx_pkg.c_forbidden, 'No principal for this database user');
  end if;
  l_outcome := item_api.request_claim(p_request);  -- the same decision code REST calls
  commit;                                           -- one transaction per call
  road_ctx_pkg.end_request;
  return l_outcome;
exception
  when others then
    rollback;
    road_ctx_pkg.end_request;
    raise;
end;
```

Rules, all from road-planner AG-10:

- The agent's database user has `EXECUTE` on the wrapper and nothing else: no table grants, no
  grant on the application package or `road_ctx_pkg`.
- One transaction per call. The wrapper is the only code in the application that commits.
- The wrapper calls the same package function the REST handler calls (definition 5.6).

## 5. Tests

`road_ctx_pkg_test`, 15 tests, 2 new:

- `is_database_identity_allowed` refuses null, `ORDS_PUBLIC_USER` and the owner, and allows an
  ordinary user.
- `begin_database_request` run as the schema owner is refused and clears a previously established
  identity.

**Not covered on dev:** the accepted path (a mapped user is established; an unmapped user is not,
and no principal is created). It needs a second database user, and `ROAD_KIT_DEV` has no
`CREATE USER`. It is covered where a real agent user exists, for example road-planner's
`ROAD_PLANNER_DEV_AGENT`, when it adopts this.

## 6. Batches: deferred

The first version of this patch designed a generic batch: a JSON list of operations, a closed
reference token (`{ "created": "item", "nth": 1 }`), a `road_batch_api`, batch mode in
`road_decision_api`, declared `creates` on actions, a batch idempotency key, a dry run and an
operation limit. Simon reviewed it on 20 November 2026 and ruled it too much for the framework.

- **References are unnecessary.** A batch is ordinary PL/SQL. The application declares a local
  variable, calls the function that creates the parent, which returns the new key, and passes that
  variable to the functions that create the children. No token, no `nth`, no reference state.
  This settles design points 5.1 to 5.4 of the first version: none is needed.
- **Atomicity is the application's.** A savepoint and a rollback give all-or-nothing without the
  framework.
- **No second user yet.** road-tracker needs no batch in Release 1. road-planner's `apply_changes`
  stays application-specific until a second application needs the same thing. The todo demo stays a
  simple list (spec-patches 10 and 11 were withdrawn on the same reasoning).

Points left open if batches return: 5.5 (a batch idempotency key), 5.6 (a dry run returns
`audit_id: null`, which needs gsc definition 6.4.1 amended in its Appendix E, or writes a flagged
record) and 5.7 (a limit). Also:

1. Calls composed in one block must not commit (the wrapper in section 4 commits after each call),
   so a batch needs a way to say "do not commit until the end".
2. `road_decision_api` writes an autonomous rejection record for each rejected call. A composition
   would leave one for the failing call and one for the whole batch.

Two statements in the framework's documents say pooled sessions can carry a previous caller's
context ([database-session-context-v1.md](../spec/database-session-context-v1.md) section 9.1 and
coding-standards 6.4). Simon states that ORDS gives each call clean data. Those statements have not
been tested or changed; `begin_request` still clears first.

## 7. Out of scope

- Delegation, where an agent acts for a person (definition Appendix E question 1).
- Asynchronous or long-running work.
- A command line binding (definition Appendix E question 5).
