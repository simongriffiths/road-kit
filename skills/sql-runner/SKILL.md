---
name: sql-runner
description: Use when installing, updating, configuring, or operating the sql-runner framework for Oracle SQLcl execution, including safe SQL script runs, INTENT blocks, run logs, db-history queries, and production guardrails.
---

# sql-runner

Use this skill for Oracle Database project work that should run SQL through the `sql-runner` framework.

## Core Rule

Do not run project SQL directly with `sql` when `bin/run-sql.sh` is available. Do not run another project's SQL with the central `sql-runner` checkout. Install or update `sql-runner` into the target project, change to that project root, then use the project-local runner:

```bash
cd <project-root>
bin/run-sql.sh --env <env> --script <file.sql>
```

## Install Or Update

If the current project does not have `bin/run-sql.sh`, offer to install it from the source repo:

```bash
skills/sql-runner/scripts/install-sql-runner.sh --target <project-root>
```

If this skill is installed globally without the full repository checkout, the installer fetches from:

```text
git@github.com:simongriffiths/sql-runner.git
```

After install, ask the user to configure `config/connections.conf` unless it already exists. Do not commit `config/connections.conf`.

## Required Workflow For SQL Work

1. Confirm you are in the target project root, not the central `sql-runner` source repository.
2. Confirm `bin/run-sql.sh` exists at the project root.
3. Confirm `config/connections.conf` exists, or identify the intended `SQL_RUNNER_CONFIG`.
4. Before changing or running SQL, search prior history when a history DB exists:
   - `bin/db-history-similar.sh "<task description>"`
   - `bin/db-history-script.sh <object-or-script-term>`
   - `bin/db-history-failures.sh <term>`
5. Ensure the SQL script has an `INTENT` block near the top.
6. Run SQL only through the target project's `bin/run-sql.sh --env <env> --script <file.sql>`.
7. For production, require explicit user confirmation and `ALLOW_PROD_SQL=yes`.
8. After execution, review:
   - console status
   - log file path
   - `USER_ERRORS` section
   - SQLite history record when available
9. Do not repeat a previously failed approach unless the new attempt explains why it differs.

## INTENT Block

Use this shape:

```sql
-- INTENT:
-- Purpose: Add customer preference storage.
-- Approach: Create CUSTOMER_PREFS rather than extending CUSTOMER.
-- Reason: Preferences evolve independently.
-- Expected objects:
--   CUSTOMER_PREFS
--   CUSTOMER_PREFS_PK
-- Risk: Low
-- Prior history checked: None found.
-- END INTENT
```

## Commands

- Run SQL: `bin/run-sql.sh --env dev --script path/to/script.sql`
- Debug SQLcl output: `bin/run-sql.sh --env dev --script path/to/script.sql --log-level debug`
- Rebuild history: `bin/db-history-init.sh --rebuild`
- Recent runs: `bin/db-history-recent.sh [env] [limit]`
- Failures: `bin/db-history-failures.sh [term]`
- Similar history: `bin/db-history-similar.sh "<description>"`
- Script/object history: `bin/db-history-script.sh <term> [limit]`
- Commit history: `bin/db-history-commit.sh <commit-prefix> [limit]`
- Show run: `bin/db-history-show.sh <run_id-or-prefix>`

## References

Read `references/workflow.md` when you need more detail on installation, production safety, or post-run review.
