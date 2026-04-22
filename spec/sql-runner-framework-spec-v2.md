# SQL Runner Framework Specification
**Version:** 2.0 — Amended  
**Status:** Resolved (16 issues incorporated)

---

## 1. Goals

- Deterministic execution of SQL scripts with explicit ordering
- Clear, debuggable logs with two verbosity levels
- Strict propagation of failures via exit codes
- One-file-per-artifact for traceability
- Support for selective cleanup and full teardown
- Codex/CI-friendly execution model
- No dependency inference (manual ordering only)

---

## 2. Non-Goals

- No automatic dependency graph resolution
- No Liquibase-style change tracking
- No implicit schema diffing
- No hidden execution (all SQL must be visible or materialised)

---

## 3. Core Principles

1. Explicit over implicit
2. Artifacts are first-class units
3. Execution must be observable
4. Failure must be unambiguous
5. Logs must be sufficient for offline diagnosis
6. Same runner for deploy and test

---

## 4. Directory Structure

```
db/
  tables/
  indexes/
  synonyms/
  views/
  types/
  package_specs/
  package_bodies/
  type_bodies/
  standalone/
api/
  modules/
    <module_name>/
      module.create.sql
      module.drop.sql
      privileges.create.sql
      privileges.drop.sql
deploy/
  create/
    00_full.sql
    05_types.sql
    10_tables.sql
    20_indexes.sql
    30_synonyms.sql
    40_views.sql
    60_package_specs.sql
    70_package_bodies.sql
    75_type_bodies.sql
    80_standalone.sql
    90_rest.sql
    95_data.sql
    99_verify.sql
  drop/
    00_full.sql
    90_rest.sql
    80_standalone.sql
    75_type_bodies.sql
    70_package_bodies.sql
    60_package_specs.sql
    40_views.sql
    30_synonyms.sql
    20_indexes.sql
    10_tables.sql
    05_types.sql
  test/
    00_test_setup.sql
test/
  smoke/
  contract/
logs/
  <env>/
    runs/
    generated/
bin/
  run-sql.sh
```

---

## 5. Artifact Rules

### 5.1 One File per Artifact

Each artifact must be defined in a single file.

Examples:

```
db/tables/customer.create.sql
db/views/customer_summary_v.create.sql
db/package_specs/customer_api.pks
db/package_bodies/customer_api.pkb
```

### 5.2 Partner Drop Scripts

Where applicable, artifacts must have a drop script:

```
customer.create.sql
customer.drop.sql
```

Drop scripts must:

- Succeed if object does not exist
- Raise only on unexpected errors

---

## 6. Precedence Model

Deployment order is fixed by precedence classes:

```
05_types          ← object/collection types used by tables
10_tables
20_indexes
30_synonyms
40_views
60_package_specs
70_package_bodies
75_type_bodies
80_standalone
90_rest
95_data
99_verify
```

Rules:

- No cross-class violations
- Manual ordering within each class
- No automatic dependency resolution

Teardown runs in exact reverse order.

### 6.1 Master Orchestration Scripts

`deploy/create/00_full.sql` and `deploy/drop/00_full.sql` are manually maintained master orchestration scripts. They `@`-reference the numbered scripts in explicit order and contain no business logic. They are the standard entry points for a full deploy or full teardown.

Example (`deploy/create/00_full.sql`):

```sql
prompt === full deploy ===
@deploy/create/05_types.sql
@deploy/create/10_tables.sql
@deploy/create/20_indexes.sql
@deploy/create/30_synonyms.sql
@deploy/create/40_views.sql
@deploy/create/60_package_specs.sql
@deploy/create/70_package_bodies.sql
@deploy/create/75_type_bodies.sql
@deploy/create/80_standalone.sql
@deploy/create/90_rest.sql
@deploy/create/95_data.sql
@deploy/create/99_verify.sql
```

---

## 7. Script Types

### 7.1 Create Scripts

- Use plain DDL where possible
- Fail on error
- No silent drops

### 7.2 Drop Scripts

- Use guarded dynamic SQL where needed
- Must be idempotent
- Must not mask unexpected errors

### 7.3 Generated Scripts (Dynamic DDL)

- Must be materialised to file
- Must be executed via runner
- Must be logged

### 7.4 Data Scripts

Data scripts (executed at `95_data`) must follow these rules:

- Must use `MERGE` or `INSERT ... WHERE NOT EXISTS` — plain unconditional `INSERT` is not permitted
- Must be idempotent — safe to run multiple times without error or duplicate data
- Must not use `TRUNCATE` or `DELETE` without a comment in the script header explicitly documenting the intent and risk
- Inherit the standard `whenever sqlerror exit sql.sqlcode rollback` contract

---

## 8. SQL Script Contract

Every executed SQL script must begin with:

```sql
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
```

Recommended settings:

```sql
set feedback on
set timing on
set serveroutput on size unlimited
set define off
set sqlblanklines on
```

**Note:** `set define off` is injected unconditionally by the runner. Scripts must not rely on SQLcl substitution variables (`&var`). Any script that genuinely requires substitution variable behaviour must explicitly re-enable it with `set define on` at its own top. This is a documented framework constraint, not a bug.

Debug mode may additionally enable:

```sql
set echo on
```

---

## 9. Test and Assertion Model

### 9.1 assert_true Procedure

The assertion utility lives at:

```
db/standalone/assert_true.prc
```

It is deployed via `deploy/test/00_test_setup.sql` and must **not** be included in `deploy/create/00_full.sql`. It is a test-only utility.

CI pipelines must run `deploy/test/00_test_setup.sql` before executing anything under `test/`.

Definition:

```sql
create or replace procedure assert_true(
  p_condition boolean,
  p_message   varchar2
) is
begin
  if not nvl(p_condition, false) then
    raise_application_error(-20000, p_message);
  end if;
end;
/
```

### 9.2 Test Output Format

Optional structured output:

```
[TEST] name
[PASS] message
[FAIL] message
[RESULT] PASS|FAIL
```

Failure must result in non-zero exit via SQLERROR.

### 9.3 Test Directories

**`test/smoke/`**  
Fast, post-deploy sanity checks. Verify objects exist, are accessible, and return expected shapes. No business logic assertions. Should complete in seconds.

**`test/contract/`**  
Behavioural assertions against package APIs and views. Use `assert_true`. Test known inputs produce expected outputs. May use test data.

Both directories inherit the standard script contract. Naming convention: `<object_name>.test.sql`.

---

## 10. Runner CLI

```bash
run-sql.sh --env <env> --script <file.sql> [--log-level normal|debug]
```

Arguments:

- `--env` (required): environment name
- `--script` (required): SQL script path, relative to project root
- `--log-level` (optional): `normal` or `debug`, default = `normal`

The runner must be invoked from the project root. Script paths are always relative to project root.

---

## 11. Environment Model

Environment maps to a named SQLcl CONNMGR connection:

```
dev  -> app_dev
test -> app_test
prod -> app_prod
```

Connections are managed via SQLcl CONNMGR. No inline credentials are permitted.

### 11.1 CONNMGR as Prerequisite

CONNMGR connections must be provisioned before using the framework. The runner does not create them.

**Developer setup (once per environment):**

```bash
sql /nolog
connect -save app_dev --url jdbc:oracle:thin:@<host>:<port>/<service> --username <user>
```

**CI setup:**  
Connections must be provisioned as part of the pipeline setup step, before any `run-sql.sh` call.

A `bin/setup-connections.sh` helper script is a planned v2 addition.

---

## 12. Logging Model

### 12.1 Log File Location

Each run produces one log file:

```
logs/<env>/runs/<timestamp>_<script_base>_<pid>.log
```

Example:

```
logs/dev/runs/20260418_131455_customer_create_12345.log
```

Where:
- `<timestamp>` = `YYYYMMDD_HHMMSS`
- `<script_base>` = `basename` of script path, extension stripped
- `<pid>` = shell PID (`$$`)

The runner must create the parent directory if needed. If directory creation fails, the runner must print a clear error to stderr and exit with code 2 without invoking SQLcl.

### 12.2 Log Levels

**Normal**

Console shows:

- start/end
- script name
- environment
- exit code
- log location

SQLcl output is written to the log file only. Runner lifecycle messages are printed to console separately via `echo`.

**Debug**

Console shows:

- full SQLcl output (via `tee`)
- internal runner details
- resolved paths
- SQL session verbosity (`set echo on`)

In both modes, full raw SQLcl output (stdout and stderr) must be written to the log file.

### 12.3 Log Content Requirements

Each log must contain:

```
[INFO] START
[INFO] ENV=<env>
[INFO] CONNECTION=<connection_name>
[INFO] SCRIPT=<script_path>
[INFO] LOG_LEVEL=<level>
[INFO] TIMESTAMP=<timestamp>
[INFO] SQLCL_EXIT=<code>
[INFO] END
```

---

## 13. Exit Code Semantics

| Condition | Exit Code |
|---|---|
| Success | 0 |
| SQL error | SQLCODE |
| OS error | non-zero |
| Script missing | 2 |
| Invalid env | 2 |
| Invalid arguments | 2 |
| Log directory creation failure | 2 |
| SQLcl not found | 127 |

Rules:

- Runner must return SQLcl exit code unchanged
- No swallowing of errors
- No "success with warnings" mode

---

## 14. Execution Model

All execution flows through the runner.

Example — single artifact:

```bash
run-sql.sh --env dev --script deploy/create/10_tables.sql
```

Example — full deploy:

```bash
run-sql.sh --env dev --script deploy/create/00_full.sql
```

Example — generated script:

```bash
run-sql.sh --env dev --script logs/dev/generated/gen_tables.sql
```

---

## 15. Orchestration Scripts

Orchestration scripts:

- Define order explicitly
- Only reference artifact scripts via `@`
- Contain no business logic

Example:

```sql
prompt === tables ===
@db/tables/customer.create.sql
@db/tables/order_header.create.sql
```

### 15.1 REST Module Assembly

`deploy/create/90_rest.sql` is a manually maintained orchestration script. It `@`-references each module's scripts in explicit order. Adding a new ORDS module requires manually adding the references.

Example:

```sql
prompt === rest modules ===
@api/modules/customer/module.create.sql
@api/modules/customer/privileges.create.sql
@api/modules/orders/module.create.sql
@api/modules/orders/privileges.create.sql
```

---

## 16. Teardown Model

Teardown scripts:

- Call partner drop scripts
- Follow reverse precedence
- Must be safe for repeated execution

`deploy/drop/00_full.sql` is the master teardown entry point, mirroring `deploy/create/00_full.sql` in reverse precedence order.

---

## 17. Codex Integration Contract

Codex must:

- Only call `run-sql.sh`
- Never execute SQL directly
- Never embed credentials
- Always specify environment
- Treat non-zero exit as failure

---

## 18. Future Extensions (Not in v1)

- JSON log summaries
- Parallel test execution
- Retry for transient failures
- Expected-failure test mode
- Artifact metadata tagging
- `bin/setup-connections.sh` for CONNMGR provisioning

---

## 19. Key Rules Summary

- One artifact per file
- Partner drop scripts required where applicable
- Manual ordering only
- Precedence enforced
- Dynamic SQL must be materialised
- Runner is single execution entrypoint
- Non-zero means failure, always
- Data scripts must be idempotent
- Test utilities are never deployed to production schema
- CONNMGR connections must be provisioned before use
