# CI/CD Pipeline
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines the deployment pipeline for applications built on this framework. It covers environment promotion rules, test gates, and the deployment sequence for both database objects and React applications. The pipeline is agent-driven in v1 with no external CI platform dependency, but is designed to be adoptable by GitHub Actions or OCI DevOps without structural changes.

---

## 2. Core Principles

1. **Three environments.** All applications have dev, test, and prod environments. No shortcuts to prod.
2. **Tests gate promotion.** Promotion to the next environment requires all tests to pass in the current environment.
3. **Manual gate before prod.** Promotion from test to prod requires explicit manual approval. Automated promotion stops at test.
4. **Pipeline is a sequence of existing tools.** The pipeline calls `run-sql.sh`, `bin/deploy-react.sh`, and `bin/run-endpoint-tests.sh`. It adds orchestration, not new behaviour.
5. **Non-zero exits halt the pipeline.** Any failure at any step stops execution. There is no "continue on error" mode.

---

## 3. Environments

| Environment | Purpose | Promotion Gate |
|---|---|---|
| `dev` | Active development and initial verification | All tests pass |
| `test` | Stable integration environment | All tests pass + manual approval |
| `prod` | Production | N/A — terminal environment |

Each environment maps to:
- A named SQLcl saved connection (`app_dev`, `app_test`, `app_prod`)
- A separate ADB ORDS instance or URL base-path configuration for API and UI delivery
- Its own wallet configuration under `/opt/oracle/wallet/<app_name>-<env>/`

---

## 4. Pipeline Stages

### 4.1 Stage Overview

```
┌─────────────────────────────────────────┐
│  DEPLOY                                 │
│  1. Deploy database objects             │
│  2. Deploy React app                    │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  TEST                                   │
│  3. Deploy test utilities               │
│  4. Run SQL smoke tests                 │
│  5. Run SQL contract tests              │
│  6. Run HTTP endpoint tests             │
│  7. Run React component tests           │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  PROMOTE (if env != prod)               │
│  8. If dev → test: auto-promote         │
│  9. If test → prod: await approval      │
└─────────────────────────────────────────┘
```

### 4.2 Stage 1 — Deploy Database Objects

```bash
run-sql.sh --env <env> --script deploy/create/00_full.sql
```

On first deploy this creates all objects. On subsequent deploys, drop scripts must be run first (or objects must be created with `create or replace` where supported).

### 4.3 Stage 2 — Deploy React App

```bash
bin/deploy-react.sh --env <env> --app <app_name>
```

Builds the React app for the target environment and uploads the resulting static files through the ROAD UI delivery model defined in `file-upload-and-ui-delivery-spec-v1.md`.

Environment mapping for the UI build:

- `dev` uses Vite `development` mode and `.env.development`
- `test` uses Vite `test` mode and `.env.test`
- `prod` uses Vite `production` mode and `.env.production`

### 4.4 Stage 3 — Deploy Test Utilities

```bash
run-sql.sh --env <env> --script deploy/test/00_test_setup.sql
```

Deploys `assert_true` and any other test-only utilities. Must not run in prod (see Section 6).

### 4.5 Stage 4 — SQL Smoke Tests

```bash
run-sql.sh --env <env> --script test/smoke/00_smoke.sql
```

Fast post-deploy sanity checks. Must complete in under 30 seconds.

### 4.6 Stage 5 — SQL Contract Tests

```bash
run-sql.sh --env <env> --script test/contract/00_contract.sql
```

Behavioural assertions against packages and views.

### 4.7 Stage 6 — HTTP Endpoint Tests

```bash
bin/run-endpoint-tests.sh --env <env>
```

Verifies ORDS wiring, HTTP status codes, and response shapes.

### 4.8 Stage 7 — React Component Tests

```bash
cd <app_name> && npm run test:ci
```

Runs Vitest component tests. Does not require ADB connectivity.

### 4.9 Stage 8 — Promotion

**dev → test (automatic)**

If all stages 1–7 pass against `dev`, the pipeline automatically re-runs stages 1–7 against `test`.

**test → prod (manual gate)**

If all stages 1–7 pass against `test`, the pipeline pauses and emits a promotion request:

```
[PIPELINE] All tests passed in test environment.
[PIPELINE] Awaiting manual approval to promote to prod.
[PIPELINE] Run: bin/pipeline.sh --env prod --app <app_name> to proceed.
```

Prod deployment only proceeds when explicitly invoked. It runs stages 1–2 only (no test utilities, no test execution in prod — see Section 6).

---

## 5. Pipeline Entry Point

The pipeline is driven by a single script:

```bash
bin/pipeline.sh --env <env> --app <app_name>
```

Arguments:

- `--env` (required): target environment (`dev`, `test`, `prod`)
- `--app` (required): application name

Behaviour:

- `dev`: runs all stages 1–7, then triggers `test` automatically if all pass
- `test`: runs all stages 1–7, then emits prod promotion request if all pass
- `prod`: runs stages 1–2 only (deploy only, no tests)

`bin/pipeline.sh` logs to:

```
logs/<env>/runs/<timestamp>_pipeline_<app>_<pid>.log
```

---

## 6. Environment-Specific Rules

### 6.1 Prod Restrictions

The following must never run against prod:

- `deploy/test/00_test_setup.sql` — test utilities must not exist in prod
- Any script under `test/`
- `bin/run-endpoint-tests.sh`
- `npm run test:ci`

`bin/pipeline.sh` enforces this — when `--env prod` is specified, test stages are skipped unconditionally.

### 6.2 Teardown

Teardown is never part of an automated pipeline run. It must always be invoked manually:

```bash
run-sql.sh --env <env> --script deploy/drop/00_full.sql
```

Teardown is available for dev and test only. There is no automated teardown for prod.

---

## 7. Failure Handling

| Failure Point | Behaviour |
|---|---|
| Database deploy fails | Pipeline halts, no React deploy attempted |
| React deploy fails | Pipeline halts, no tests run |
| Any test stage fails | Pipeline halts, no promotion attempted |
| Prod promotion invoked without prior test pass | Not enforced in v1 — agent responsibility |

All failures are logged to the pipeline log file. The agent must treat any non-zero pipeline exit as a hard failure requiring investigation before retry.

---

## 8. Pipeline Log

Each pipeline run produces a top-level log at:

```
logs/<env>/runs/<timestamp>_pipeline_<app>_<pid>.log
```

This log contains:

```
[PIPELINE] START
[PIPELINE] ENV=<env>
[PIPELINE] APP=<app>
[PIPELINE] TIMESTAMP=<timestamp>
[PIPELINE] STAGE=<n> <stage_name> START
[PIPELINE] STAGE=<n> <stage_name> EXIT=<code>
...
[PIPELINE] RESULT=PASS|FAIL
[PIPELINE] END
```

Individual stage logs (from `run-sql.sh`, endpoint tests, etc.) are written to their own files as normal and referenced from the pipeline log.

---

## 9. Future Extensions (Not in v1)

- External CI platform integration (GitHub Actions, OCI DevOps)
- Automated prod promotion with approval workflow (pull request gate, Slack approval)
- Rollback on failed prod deployment
- Parallel test execution
- Deployment notifications
- Pipeline status dashboard

---

## 10. What This Spec Does Not Cover

- OCI console setup for additional environments
- Wallet provisioning for test and prod (manual prerequisite — see Local Development Environment Spec)
- ORDS privilege and security configuration per environment (see `ords-security-configuration-v1.md`)
- React build caching or optimisation
