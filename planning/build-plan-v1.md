# ROAD Build Plan
**Version:** 1.0  
**Status:** Proposed  
**Baseline:** `spec/spec-baseline-v1.md`

---

## 1. Purpose

This document turns the frozen ROAD specification baseline into a phased implementation plan.

It is not a normative spec. It is a delivery plan for building the first executable version of the framework from the current frozen baseline.

---

## 2. Planning Assumptions

- The frozen design baseline is `spec/spec-baseline-v1.md`
- Historical briefing documents are non-normative and must not drive implementation decisions
- The repo will evolve from a spec-only repository into a working framework repository
- `APP_NAME` in `road.config` is the canonical project identity
- Production must use the hosted ADB ORDS deployment model
- Development and test may use local runtime tooling where useful, but the standard build path should target hosted ORDS
- Oracle-specific build work should use the available `oracle-db-skills` reference set for SQL, PL/SQL, ORDS, SQLcl, and Oracle security guidance

---

## 3. Delivery Strategy

The framework should not be built all at once.

The implementation should proceed in four controlled stages:

1. Foundation and bootstrap
2. First runnable hosted slice
3. First protected vertical slice
4. Hardening and pipeline completion

Each stage should leave the repository in a runnable, testable state.

For Oracle-specific implementation work, the build should prefer the local `oracle-db-skills` guidance set as the first reference source before inventing patterns ad hoc.

---

## 4. Stage 1: Foundation And Bootstrap

### 4.1 Goal

Create the minimum repository structure and tooling required to make ROAD executable as a framework project rather than only a spec set.

### 4.2 Deliverables

- repo-root `road.config`
- repo-root `.env.example` guidance where needed
- `bin/` directory with placeholder executable scripts
- base SQL artifact directories from the SQL runner specs
- base test directories from the testing spec
- a minimal React app skeleton built with Vite and TypeScript
- a canonical folder layout for the first app implementation

### 4.3 Required Files

At minimum:

```text
road.config
bin/run-sql.sh
bin/deploy-react.sh
bin/pipeline.sh
bin/run-endpoint-tests.sh
bin/get-test-token.sh
bin/assert-http.sh
bin/verify-connection.sql
db/
api/modules/
deploy/create/
deploy/drop/
deploy/test/
test/smoke/
test/contract/
test/endpoint/
<app_name>/
```

### 4.4 Acceptance Criteria

- `road.config` exists and defines `APP_NAME`
- script entry points exist and are executable
- directory structure matches the frozen specs
- the React app can run `npm install` and `npm run build`
- no runtime behaviour is promised yet beyond basic script invocation and React build success

---

## 5. Stage 2: First Runnable Hosted Slice

### 5.1 Goal

Deliver the first complete hosted ROAD flow without taking on full auth complexity immediately.

This stage proves that the framework can:

- deploy SQL artifacts
- expose a minimal ORDS API
- build and upload a React application
- serve the UI from ORDS
- run smoke tests successfully

### 5.2 Scope

Implement one minimal public vertical slice:

- one database package
- one ORDS module
- one simple API endpoint
- one uploaded React shell
- one smoke test
- one endpoint test

### 5.3 Recommended Endpoint

Use a simple health or bootstrap endpoint first, for example:

```text
GET /ords/<api_base_path>/api/v1/health/
```

Response:

```json
{
  "status": "ok"
}
```

This keeps the first executable slice focused on framework plumbing rather than authentication edge cases.

### 5.4 Deliverables

- minimal schema objects needed for a health-style package
- one ORDS module and handler following the handler-thinness rule
- `run-sql.sh` able to execute deployment and smoke scripts
- `deploy-react.sh` able to build the React app and upload `dist/`
- UI delivery objects sufficient to serve `index.html` and static assets
- a minimal React shell page that calls the health endpoint through the central API client

### 5.5 Acceptance Criteria

- `run-sql.sh --env dev --script deploy/create/00_full.sql` succeeds
- `bin/deploy-react.sh --env dev --app <app_name>` succeeds
- the UI is reachable at `/ords/<ui_base_path>/ui/<app_name>/`
- the health endpoint returns `200`
- the React shell can load and display a successful API response
- smoke and endpoint tests pass in `dev`

---

## 6. Stage 3: First Protected Vertical Slice

### 6.1 Goal

Add the first real protected API flow and prove that the auth boundary works end to end.

### 6.2 Scope

Implement one authenticated slice after the hosted foundation is stable:

- token acquisition path for test usage
- one protected ORDS endpoint
- one PL/SQL package using session context
- one React auth flow sufficient to store a token in `sessionStorage`
- one protected React route
- endpoint tests covering unauthenticated and wrong-scope rejection

### 6.3 Recommended Endpoint

Use a minimal identity endpoint, for example:

```text
GET /ords/<api_base_path>/api/v1/session/me/
```

That endpoint is a good first protected slice because it exercises:

- JWT handling
- ORDS protection
- session-context mapping
- React token storage
- protected routing

without requiring full business-domain complexity.

### 6.4 Deliverables

- auth provider integration for the chosen dev/test path
- ORDS privilege and protection configuration for one endpoint
- session-context package wiring sufficient to expose caller identity
- React login/bootstrap path sufficient to obtain and store a token
- protected route guard and `401` handling

### 6.5 Acceptance Criteria

- unauthenticated request returns `401`
- authenticated request with valid access returns `200`
- authenticated request without required privilege/scope returns `401` at the ORDS boundary in the v1 ORDS-first profile
- React stores token only through `src/utils/auth.ts`
- protected route redirects correctly when not authenticated
- endpoint tests and component tests covering this slice pass

---

## 7. Stage 4: Hardening And Pipeline Completion

### 7.1 Goal

Move from a working framework skeleton to an operationally credible v1.

### 7.2 Scope

- promote placeholder scripts into production-grade implementations
- add full logging, error handling, and exit-code discipline
- complete upload sync behaviour
- complete CI pipeline orchestration
- add test token automation
- add environment promotion gates
- harden auth and ORDS security details

### 7.3 Acceptance Criteria

- `dev`, `test`, and `prod` flows are defined and executable
- pipeline runs the required deploy, test, and promotion sequence
- manual production approval remains enforced
- the first public slice and first protected slice both pass in `dev` and `test`

---

## 8. Repository Build Order

The recommended implementation order inside the repo is:

1. `road.config`
2. `bin/run-sql.sh`
3. SQL directory structure and deploy scripts
4. ORDS module structure
5. Vite React app skeleton
6. `bin/deploy-react.sh`
7. UI delivery objects
8. health endpoint and tests
9. auth bootstrap and `session/me` protected slice
10. pipeline orchestration

This order keeps the framework executable at every step and reduces the chance of building isolated pieces that cannot yet be verified.

---

## 9. Explicitly Out Of Scope For The First Runnable Slice

The first runnable slice should not attempt all of the following at once:

- full domain model implementation
- multiple business APIs
- broad privilege matrix design
- production auth hardening for every provider variant
- full UI asset sync edge cases
- complete CI/CD production automation
- advanced frontend design system choices

Those belong after the first hosted slice is already working.

---

## 10. Suggested First Build Ticket Set

The first implementation batch should be split into these tickets:

1. Create repo runtime skeleton and `road.config`
2. Implement `bin/run-sql.sh` and `bin/verify-connection.sql`
3. Create minimal deployment SQL structure and `00_full.sql`
4. Scaffold Vite React app with `VITE_APP_NAME`, `VITE_UI_BASE_PATH`, and API client
5. Implement `bin/deploy-react.sh`
6. Implement database-backed UI delivery objects
7. Implement `GET /health/` public slice
8. Add smoke and endpoint tests for the public slice
9. Implement minimal auth bootstrap and `GET /session/me/`
10. Add protected-route and auth tests

---

## 11. Build Gate

Implementation should start with Stage 1 only.

Stage 2 should not begin until:

- the repo skeleton exists
- configuration flow from `road.config` is working
- the React app builds successfully
- SQL deployment tooling is executable

Stage 3 should not begin until the Stage 2 hosted public slice is working end to end.
