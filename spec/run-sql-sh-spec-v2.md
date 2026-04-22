# run-sql.sh Specification
**Version:** 2.0 — Amended  
**Status:** Resolved (issues 8–16 incorporated)

---

## 1. Purpose

`run-sql.sh` is the single approved shell entry point for executing SQL scripts through SQLcl in a controlled, repeatable, and observable way.

It must provide:

- Deterministic script execution
- Consistent log creation
- Strict propagation of SQLcl exit codes
- Environment-to-connection resolution
- Two log levels: `normal` and `debug`

It is intended to be used by developers, Codex, and CI/CD automation.

---

## 2. Scope

`run-sql.sh` is responsible for:

- Validating input arguments
- Resolving the target environment to a SQLcl connection name
- Creating run log files
- Invoking SQLcl in a consistent way
- Ensuring SQL and OS errors return non-zero
- Returning the final process exit code to the caller

`run-sql.sh` is not responsible for:

- Inferring deployment dependencies
- Discovering artifact order
- Modifying SQL scripts dynamically
- Embedding credentials
- Parsing business-level test output
- Provisioning CONNMGR connections

---

## 3. Command-Line Interface

```bash
run-sql.sh --env <env> --script <file.sql> [--log-level normal|debug]
```

### 3.1 Required Arguments

`--env <env>`  
Logical environment name.

`--script <file.sql>`  
Path to the SQL script to execute, relative to project root.

### 3.2 Optional Arguments

`--log-level normal|debug`  
Controls console verbosity and SQLcl session verbosity.  
Default: `normal`

### 3.3 Invalid Usage

If required arguments are missing, unknown options are supplied, or values are invalid (including an unrecognised `--log-level` value), the script must:

- Print usage to stderr
- Exit with code 2

---

## 4. Configuration Block

The script must define a clearly marked configuration block near the top:

```bash
# --- Configuration ---
SQLCL_BIN="${SQLCL_BIN:-sql}"
```

`SQLCL_BIN` defaults to `sql` but can be overridden by setting the environment variable before invocation. This supports non-standard install paths and CI environments without modifying the script.

---

## 5. Environment Resolution

The script must not accept raw connection strings.

It must resolve logical environments to stored SQLcl saved connections.

Mapping (isolated in one section for easy refactoring):

```
dev   -> app_dev
test  -> app_test
prod  -> app_prod
```

If the environment is unknown, the script must:

- Print a clear error to stderr
- Exit with code 2

---

## 6. Preconditions

Before attempting execution, the script must verify in this order:

1. Required arguments are present and valid
2. Log parent directory exists or can be created
3. The target SQL script exists and is a regular file
4. `$SQLCL_BIN` is available on PATH (`command -v`)

If any check fails:

| Condition | Exit Code |
|---|---|
| Invalid arguments | 2 |
| Log directory creation failure | 2 |
| Missing or invalid script | 2 |
| SQLcl binary not found | 127 |

All errors must print a clear message to stderr. No SQLcl invocation must occur if any precondition fails.

---

## 7. Logging Requirements

### 7.1 Log File Location

Each execution must create one run log file:

```
logs/<env>/runs/<timestamp>_<script_base>_<pid>.log
```

Example:

```
logs/dev/runs/20260418_131455_customer_summary_v.create_12345.log
```

Where:
- `<timestamp>` = `YYYYMMDD_HHMMSS`
- `<script_base>` = `basename` of script path, `.sql` extension stripped
- `<pid>` = `$$` (shell PID, guarantees collision-free filenames under parallel CI execution)

### 7.2 Log Directory Creation

The script must create the parent directory using `mkdir -p`. If `mkdir -p` fails, the script must:

- Print a clear error to stderr identifying the path it failed to create
- Exit with code 2
- Not invoke SQLcl

### 7.3 Log Content

Each run log must contain enough information to diagnose execution offline.

Required markers:

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

Full raw SQLcl output (stdout and stderr merged) must also be written to the log in both modes.

### 7.4 Console Behaviour

**normal**

Console output is concise. The runner prints lifecycle messages via `echo`:

- Start
- Environment and connection name
- Script path
- Log file path
- Final success or failure
- Final exit code

SQLcl output is written to the log file only — not to the console in normal mode.

**debug**

Console output additionally includes full SQLcl output via `tee`. Internal runner details and resolved paths may also be printed.

---

## 8. SQLcl Invocation Contract

### 8.1 Invocation Pattern

SQLcl must be driven via a here-doc to ensure the session settings and error handling are injected before the target script runs:

```bash
"${SQLCL_BIN}" -name "${CONNECTION}" 2>&1 <<EOF | tee "${LOG_FILE}"
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set feedback on
set timing on
set serveroutput on size unlimited
set define off
set sqlblanklines on
${ECHO_SETTING}
@${SCRIPT}
exit success
EOF
SQLCL_EXIT=$?
```

Where `ECHO_SETTING` is:
- `set echo on` in debug mode
- `set echo off` in normal mode

### 8.2 stderr Handling

stderr must be merged into stdout before the pipe (`2>&1`) so that all output — including connection errors and OS-level failures — is captured in the log.

### 8.3 Exit Code Capture

`SQLCL_EXIT=$?` must be assigned immediately after the here-doc closes, before any other shell command executes.

`set -o pipefail` must be set at the top of the script to ensure the exit code of the pipeline reflects SQLcl's exit code, not `tee`'s.

### 8.4 tee Behaviour by Log Level

**normal:** SQLcl output is directed to the log file only. `tee` writes to the log; console output from SQLcl is suppressed. Runner lifecycle messages are printed separately via `echo`.

**debug:** `tee` writes to both the log file and stdout, making full SQLcl output visible on the console.

### 8.5 set define off

`set define off` is injected unconditionally. This is a framework constraint. Scripts must not rely on SQLcl substitution variables (`&var`). Any script that genuinely requires substitution variable behaviour must explicitly include `set define on` at its own top.

---

## 9. Exit Code Semantics

The runner must preserve the final SQLcl exit status without modification.

| Condition | Exit Code |
|---|---|
| Success | 0 |
| SQL/PLSQL error | SQLCODE (from `exit sql.sqlcode`) |
| OS error | non-zero |
| Invalid arguments | 2 |
| Missing script | 2 |
| Unknown environment | 2 |
| Log directory creation failure | 2 |
| SQLcl binary not found | 127 |
| Saved connection failure | non-zero (treated as SQL/OS error) |

Rules:

- Runner must return SQLcl exit code unchanged
- `set -o pipefail` ensures the pipe does not swallow SQLcl's exit code
- No "success with warnings" mode
- No mode where a non-zero SQLcl result is reported as success
- If SQLcl reports SQL*Plus-style session errors such as `SP2-` messages or `Unknown connection` while still returning `0`, the runner must treat the run as failed and return non-zero

---

## 10. Saved Connection Failures

If the named saved connection does not exist or the connection attempt fails:

- SQLcl will raise an error caught by `whenever oserror` or `whenever sqlerror`
- The runner will receive a non-zero exit code
- The error output will be captured in the log
- The runner will report failure with the SQLcl exit code
- No retry or fallback is attempted

Saved SQLcl connections are a prerequisite. The runner does not create or validate them beyond attempting to connect. See the Framework Specification Section 11.1 for provisioning instructions.

---

## 11. Script Execution Semantics

The runner executes exactly one target script per invocation.

It does not inspect the contents of the script beyond existence checks.

The runner may execute:

- An artifact script (`db/tables/customer.create.sql`)
- An orchestration script (`deploy/create/00_full.sql`)

It does not decide which is correct — that is the caller's responsibility.

---

## 12. Security Requirements

The runner must not:

- Embed database passwords
- Print credentials to console or log
- Accept raw connection strings on the command line

The runner must use named SQLcl CONNMGR connections only.

Debug output must not expose secrets. If `set echo on` is active, scripts that print sensitive values are responsible for suppressing them.

---

## 13. Portability Assumptions

Version 1 assumes:

- Unix-like shell environment
- Bash available
- `set -o pipefail` supported (bash 3.1+)
- SQLcl installed and resolvable via `$SQLCL_BIN`
- Writable local filesystem for logs

Cross-platform support for Windows is out of scope for version 1.

---

## 14. Observability Requirements

After any run it must be possible to answer:

- Which environment was targeted?
- Which script ran?
- What connection name was used?
- When did it run?
- Where is the full log?
- What exit code did SQLcl return?

These are the minimum observability requirements and are satisfied by the log content spec in Section 7.3.

---

## 15. Recommended Internal Structure

```
1.  set -euo pipefail
2.  Configuration block (SQLCL_BIN etc.)
3.  usage()
4.  Argument parsing
5.  Validation (arguments, log-level values)
6.  Environment resolution
7.  Precondition checks (log dir, script exists, SQLCL_BIN available)
8.  Log path construction (timestamp, basename, PID)
9.  SQLcl settings preparation (ECHO_SETTING)
10. SQLcl invocation (here-doc + tee)
11. SQLCL_EXIT=$? capture
12. Final summary echo and exit $SQLCL_EXIT
```

---

## 16. Example Flows

### Successful Run

```bash
run-sql.sh --env dev --script db/views/customer_summary_v.create.sql --log-level normal
```

Expected outcome:

1. Arguments validated
2. `dev` resolved to `app_dev`
3. Log directory created if needed
4. Script existence confirmed
5. `$SQLCL_BIN` confirmed on PATH
6. Log path constructed: `logs/dev/runs/20260418_131455_customer_summary_v.create_12345.log`
7. SQLcl invoked via here-doc
8. `SQLCL_EXIT=0` captured
9. Concise success summary printed to console
10. Exit 0

### Failed Run (SQL Error)

```bash
run-sql.sh --env dev --script db/views/bad_view.create.sql --log-level normal
```

Suppose script fails with ORA-00942.

Expected outcome:

1. SQLcl exits non-zero via `whenever sqlerror exit sql.sqlcode rollback`
2. Full output captured in log including ORA- error
3. `SQLCL_EXIT=<non_zero>` captured
4. `[INFO] SQLCL_EXIT=<non_zero>` written to log
5. Concise failure summary printed to console
6. Runner exits with the same non-zero code

---

## 17. Acceptance Criteria

`run-sql.sh` is acceptable for version 1 if all of the following are true:

- It rejects invalid arguments cleanly (exit 2)
- It resolves logical environments to named SQLcl saved connections
- It writes logs to `logs/<env>/runs/<timestamp>_<script_base>_<pid>.log`
- It supports `normal` and `debug` log levels
- It enforces `WHENEVER SQLERROR` and `WHENEVER OSERROR` via here-doc injection
- It uses `set -o pipefail` to ensure accurate exit code capture through `tee`
- It captures `SQLCL_EXIT=$?` immediately after here-doc closes
- It returns the exact SQLcl exit code on execution failure
- It never reports success on a non-zero SQLcl result
- It exposes enough information for offline diagnosis (Section 7.3)
- It never embeds or prints credentials

---

## 18. Deferred Features (v2+)

- JSON summary output
- Expected-failure mode
- Retries for transient connection failures
- Multi-script execution in one call
- External config file for environment mapping
- Artifact metadata awareness
- Structured parsing of `[PASS]`/`[FAIL]` markers
- `bin/setup-connections.sh` for CONNMGR provisioning

---

## 19. Minimal Behaviour Summary

`run-sql.sh` is a strict SQLcl wrapper that executes one script against one named environment, writes a timestamped collision-free log, and returns the true success or failure status without ambiguity.
