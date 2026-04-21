# Oracle ADB + ORDS + React Framework — Specification Index
**Version:** 1.3  
**Status:** Mixed (Approved + Draft)

---

## 1. Purpose

This document is the master index for the Oracle ADB / ORDS / React application framework. It lists all specifications, describes how they relate to each other, and provides a reading order for new developers or LLM agents working within the framework.

---

## 2. Framework Overview

This framework defines a complete, repeatable pattern for building API-first web applications on Oracle Autonomous Database. The stack is:

- **Oracle ADB** — database, PL/SQL packages, and static file hosting
- **ORDS** (built-in to ADB) — REST API layer and React static file delivery
- **React + TypeScript + Vite** — pure client-side frontend, served directly from ORDS
- **SQLcl** — database deployment and test execution
- **Bash** — pipeline orchestration

Key architectural decisions:

- API-first. The ORDS API is the public contract. The schema is an implementation detail.
- No local runtime servers in production. Development and test may use local runtime tooling, but production must run from ADB ORDS without local runtime dependencies.
- Standard ROAD deployments are same-origin. React app and API share the same host in the hosted ORDS deployment model, which is mandatory for production.
- Thin handlers. ORDS handler PL/SQL calls one package procedure. All logic is in packages.
- Agent-operated. The framework is designed for LLM agent execution, not a human team.

---

## 3. Specification Suite

### 3.0 Baseline Control

| Spec | File | Purpose |
|---|---|---|
| Specification Baseline | `spec-baseline-v1.md` | Frozen implementation baseline, included spec set, draft-by-exception list, and change-control point |

### 3.1 Database & Deployment

| Spec | File | Purpose |
|---|---|---|
| SQL Runner Framework | `sql-runner-framework-spec-v2.md` | Directory structure, artifact rules, precedence model, script contracts, test model |
| run-sql.sh | `run-sql-sh-spec-v2.md` | Shell script contract for SQLcl execution, logging, exit codes |

### 3.2 API Layer

| Spec | File | Purpose |
|---|---|---|
| ORDS API Design Standards | `ords-api-design-standards-v1.md` | URL conventions, HTTP methods, response shapes, error format, handler contract, Swagger standards |
| Error Handling Contract | `error-handling-contract-v1.md` | Error classification, server-side logging, client-side global handling, notification behaviour |
| Authentication | `authentication-spec-v1.md` | Common authentication contract, JWT claim expectations, provider profiles, and client auth lifecycle |
| ORDS Security Configuration | `ords-security-configuration-v1.md` | ORDS privileges, JWT trust configuration, and provider-specific security patterns |
| Database Session Context | `database-session-context-v1.md` | PL/SQL-facing caller identity contract and session-context expectations |
| File Upload and UI Delivery | `file-upload-and-ui-delivery-spec-v1.md` | Database-backed UI asset upload, public ORDS delivery paths, content handling, and SPA fallback |

### 3.3 Frontend

| Spec | File | Purpose |
|---|---|---|
| React Project Structure & Conventions | `react-project-structure-conventions-v1.md` | Directory layout, API client, auth conventions, component rules, TypeScript standards |

### 3.4 Environment & Operations

| Spec | File | Purpose |
|---|---|---|
| Local Development Environment | `local-dev-environment-v1.md` | ADB wallet setup, SQLcl CONNMGR, React build and deploy to ORDS, agent workflow |
| Automated Testing Strategy | `automated-testing-strategy-v1.md` | SQL tests, HTTP endpoint tests (curl), React component tests (Vitest + RTL) |
| CI/CD Pipeline | `cicd-pipeline-v1.md` | Three-environment pipeline, promotion gates, manual prod approval, pipeline entry point |

## 4. How the Specs Relate

```text
┌─────────────────────────────────────────────────────────┐
│  CI/CD Pipeline                                         │
│  Orchestrates all other layers across 3 environments    │
└────────────────────────────┬────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
┌─────────▼────────┐ ┌───────▼──────┐ ┌────────▼────────┐
│ SQL Runner       │ │ React Build  │ │ Testing         │
│ Framework        │ │ & Deploy     │ │ Strategy        │
│                  │ │              │ │                 │
│ run-sql.sh       │ │ Local Dev    │ │ SQL tests       │
│ Artifact rules   │ │ Environment  │ │ Endpoint tests  │
│ Precedence model │ │              │ │ Component tests │
└─────────┬────────┘ └───────┬──────┘ └────────┬────────┘
          │                  │                  │
          │         ┌────────▼──────────────────▼────────┐
          │         │  React Project Structure            │
          │         │  API Client, Auth, Error Handling   │
          │         └────────────────┬───────────────────┘
          │                          │
          │         ┌────────────────▼───────────────────┐
          │         │  ORDS API Design Standards          │
          └────────►│  Error Handling Contract            │
                    │  Authentication                     │
                    │  ORDS Security Configuration        │
                    │  Database Session Context           │
                    │  File Upload and UI Delivery        │
                    └────────────────────────────────────┘
```

---

## 5. Reading Order

### For a new LLM agent starting work on an application:

1. **Specification Baseline** — understand the frozen build baseline and draft-by-exception areas
2. **SQL Runner Framework** — understand the deployment model and directory structure
3. **run-sql.sh** — understand how scripts are executed
4. **Local Development Environment** — understand how to connect and deploy
5. **ORDS API Design Standards** — understand the API contract before writing any handler
6. **Error Handling Contract** — understand how errors flow before writing any package
7. **Authentication** — understand provider profiles, token lifecycle, and auth boundary rules
8. **ORDS Security Configuration** — understand privileges and JWT trust configuration
9. **Database Session Context** — understand the intended PL/SQL-facing caller identity contract
10. **React Project Structure & Conventions** — understand the frontend structure before writing any component
11. **File Upload and UI Delivery** — understand how built UI assets are uploaded and served through ORDS
12. **Automated Testing Strategy** — understand what tests are required at each layer
13. **CI/CD Pipeline** — understand the full deployment and promotion flow

### For reviewing or extending the framework:

Read the relevant spec first, then check the "What This Spec Does Not Cover" section at the bottom — each spec explicitly calls out what is handled elsewhere.

---

## 6. Key Conventions At a Glance

| Convention | Rule |
|---|---|
| SQL execution | Always via `run-sql.sh` — never direct SQLcl |
| Handler PL/SQL | Single package call only — no business logic |
| API errors | HTTP status + JSON `{error, message}` body |
| React API calls | Via central fetch wrapper only — never raw `fetch` in components |
| JWT storage | `sessionStorage` only, via `src/utils/auth.ts` only |
| Environment variables | `VITE_` prefix; API URLs are accessed via the API client, while routing/build bootstrap may read approved frontend path variables |
| Project identity | `APP_NAME` is user-supplied at bootstrap and stored canonically in repo-root `road.config` |
| Test utilities | Never deployed to prod |
| Teardown | Always manual — never automated |
| Wallet | Absolute path outside project — never committed |
| Prod promotion | Manual approval always required |

---

## 7. Key Scripts At a Glance

| Script | Purpose |
|---|---|
| `bin/run-sql.sh` | Execute a SQL script against a named environment |
| `bin/pipeline.sh` | Run full deploy + test + promotion sequence |
| `bin/deploy-react.sh` | Build React app and upload to ADB ORDS |
| `bin/run-endpoint-tests.sh` | Run all HTTP endpoint tests |
| `bin/get-test-token.sh` | Obtain a JWT for endpoint test use |
| `bin/assert-http.sh` | Assertion helper for endpoint test scripts |
| `bin/verify-connection.sql` | Smoke test for SQLcl + wallet connectivity |

---

## 8. Key Directory Locations At a Glance

| Path | Contents |
|---|---|
| `db/` | SQL artifacts — tables, views, packages, etc. |
| `api/modules/` | ORDS module scripts |
| `deploy/create/` | Ordered deployment scripts |
| `deploy/drop/` | Ordered teardown scripts |
| `deploy/test/` | Test utility deployment scripts |
| `test/smoke/` | Post-deploy sanity test scripts |
| `test/contract/` | Behavioural assertion test scripts |
| `test/endpoint/` | HTTP endpoint test scripts |
| `src/api/` | React API client and per-resource modules |
| `src/context/` | React auth and error context providers |
| `src/hooks/` | React data and auth hooks |
| `logs/` | All run logs, organised by environment |
| `road.config` | Canonical project identity such as `APP_NAME` |
| `/opt/oracle/wallet/<app_name>-<env>/` | ADB wallet — outside project, never committed |

---

## 9. Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-04-18 | Initial framework spec suite — 8 specifications |
| 1.1 | 2026-04-21 | Integrated authentication, ORDS security configuration, and database session context into the suite; external list reduced to file upload |
| 1.2 | 2026-04-21 | Integrated file upload and UI delivery into the suite; external specification list removed |
| 1.3 | 2026-04-21 | Added frozen specification baseline control document and formalised the current build baseline |
