# Automated Testing Strategy
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines the automated testing strategy for applications built on this framework. It covers three layers of testing: SQL-level contract tests, HTTP endpoint tests, and React component tests. Together these layers provide confidence that the database logic, the ORDS wiring, and the React UI all behave correctly.

---

## 2. Testing Layers

| Layer | Tool | What It Tests | When It Runs |
|---|---|---|---|
| SQL smoke tests | SQLcl + `assert_true` | Objects exist, are accessible | After every deploy |
| SQL contract tests | SQLcl + `assert_true` | Package behaviour, business logic | After every deploy |
| HTTP endpoint tests | curl + bash | ORDS wiring, HTTP status, response shape | After every deploy |
| React component tests | Vitest + React Testing Library | Component rendering, interactions | During development, in CI |

---

## 3. SQL Tests

SQL-level testing is defined in the SQL Runner Framework Specification. Key points for reference:

- Smoke tests live in `test/smoke/` — fast post-deploy sanity checks
- Contract tests live in `test/contract/` — behavioural assertions using `assert_true`
- All SQL tests run via `run-sql.sh`
- Test utilities (`assert_true`) are deployed via `deploy/test/00_test_setup.sql`
- Naming convention: `<object_name>.test.sql`

SQL tests are the primary test layer. They test all business logic directly.

---

## 4. HTTP Endpoint Tests

### 4.1 Purpose

HTTP endpoint tests verify that ORDS modules are correctly wired — that the right packages are called, the right HTTP status codes are returned, and responses conform to the API Design Standards. These tests catch failures that SQL tests cannot: missing privileges, incorrect handler bindings, misconfigured modules.

### 4.2 Tool

curl with bash. Endpoint tests follow the same conventions as the SQL runner framework — bash scripts, explicit ordering, logged output, non-zero exit on failure.

### 4.3 Directory Structure

```
test/
  endpoint/
    <resource>.endpoint.sh     ← per-resource endpoint tests
    00_endpoint.sh             ← master orchestration script
```

### 4.4 Test Script Contract

Every endpoint test script must:

- Use `set -euo pipefail`
- Print `[TEST]`, `[PASS]`, `[FAIL]` markers consistent with the SQL test output format
- Exit non-zero on any assertion failure
- Clean up any test data created during the run

### 4.5 Assertion Helper

A shared assertion helper must be defined in `bin/assert-http.sh`:

```bash
# Usage: assert_http <description> <expected_status> <actual_status> <response_body>
assert_http() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  local body="$4"

  echo "[TEST] ${description}"
  if [ "${actual}" -eq "${expected}" ]; then
    echo "[PASS] HTTP ${actual}"
  else
    echo "[FAIL] Expected HTTP ${expected}, got HTTP ${actual}"
    echo "[FAIL] Response: ${body}"
    exit 1
  fi
}
```

### 4.6 curl Conventions

All curl calls must:

- Use `-s` (silent — no progress output)
- Use `-w "%{http_code}"` to capture the HTTP status code separately from the body
- Include the `Authorization: Bearer <token>` header for protected endpoints
- Set `Content-Type: application/json` for POST/PUT/PATCH requests
- Use `-o` to write the response body to a temp file for inspection

Standard pattern:

```bash
RESPONSE_FILE=$(mktemp)
STATUS=$(curl -s -w "%{http_code}" \
  -H "Authorization: Bearer ${TEST_TOKEN}" \
  -o "${RESPONSE_FILE}" \
  "${ORDS_BASE_URL}/customers/")
BODY=$(cat "${RESPONSE_FILE}")
rm "${RESPONSE_FILE}"

assert_http "GET /customers/ returns 200" 200 "${STATUS}" "${BODY}"
```

### 4.7 Test Token

Endpoint tests require a valid JWT for protected endpoints. The test token must be:

- Obtained via the auth endpoint at the start of the test run
- Stored in a `TEST_TOKEN` variable
- Not hardcoded or committed to source control

A helper script `bin/get-test-token.sh` must obtain the token using test credentials from environment variables:

```bash
TEST_TOKEN=$(bin/get-test-token.sh --env "${ENV}")
export TEST_TOKEN
```

Test credentials must be set as environment variables before running endpoint tests — never hardcoded in scripts.

### 4.8 What to Test Per Endpoint

Every endpoint must have tests covering at minimum:

| Test Case | Expected Status |
|---|---|
| Happy path — valid request | 200 / 201 |
| Missing required parameter | 400 |
| Resource not found | 404 |
| Unauthenticated (no token) | 401 |
| Response shape includes required fields | 200 |

Additional test cases for business rule violations (422) and permission checks (403) where applicable.

### 4.9 Running Endpoint Tests

```bash
bin/run-endpoint-tests.sh --env dev
```

This script:

1. Obtains a test token via `bin/get-test-token.sh`
2. Runs `test/endpoint/00_endpoint.sh`
3. Logs output to `logs/<env>/runs/<timestamp>_endpoint_tests_<pid>.log`
4. Returns non-zero on any failure

### 4.10 Master Orchestration

`test/endpoint/00_endpoint.sh` references all resource endpoint tests in explicit order:

```bash
source bin/assert-http.sh

echo "[INFO] Starting endpoint tests"

bash test/endpoint/customers.endpoint.sh
bash test/endpoint/order_items.endpoint.sh

echo "[INFO] Endpoint tests complete"
```

---

## 5. React Component Tests

### 5.1 Purpose

Component tests verify that React components render correctly and respond to user interactions as expected. They run against a local Vite build — not against ADB ORDS — and are the only context in which a local server is used.

### 5.2 Tool

Vitest + React Testing Library.

Vitest is the natural choice for Vite-based React projects — it shares the same config and transformation pipeline.

### 5.3 Local Test Server

A local Vite dev server is used exclusively for component testing. It is never used for development or deployment. The local server:

- Runs only during test execution
- Is started and stopped by the test runner
- Does not require ADB connectivity — API calls are mocked

### 5.4 Directory Structure

Component tests live alongside their components:

```
src/
  components/
    common/
      Toast.tsx
      Toast.test.tsx
    <feature>/
      <Component>.tsx
      <Component>.test.tsx
  hooks/
    useCustomers.ts
    useCustomers.test.ts
```

### 5.5 Mocking ORDS API Calls

Component tests must not make real HTTP calls to ORDS. All API calls must be mocked at the module level:

```typescript
// Mock the API module
vi.mock('../api/customers', () => ({
  getCustomers: vi.fn().mockResolvedValue({
    items: [{ id: 1, name: 'Acme Ltd' }],
    hasMore: false,
    limit: 25,
    offset: 0,
    count: 1
  })
}));
```

The real ORDS responses are tested by the HTTP endpoint tests. Component tests verify rendering and interaction only.

### 5.6 What to Test Per Component

| Test Type | What to Assert |
|---|---|
| Render | Component renders without error |
| Loading state | Loading indicator shown while data is fetching |
| Data display | Correct data rendered when API resolves |
| Empty state | Correct empty state rendered when items is `[]` |
| User interaction | Click/input handlers call the correct functions |
| Error state | Error display when API rejects (where applicable) |

### 5.7 Running Component Tests

```bash
cd <app_name>
npm test
```

Or for CI:

```bash
npm run test:ci   # runs once, no watch mode, exits with code
```

`package.json` must define both `test` (watch mode) and `test:ci` (single run) scripts.

---

## 6. Test Execution Order

The full test suite runs in this order:

```
1. run-sql.sh --env <env> --script deploy/test/00_test_setup.sql
2. run-sql.sh --env <env> --script test/smoke/00_smoke.sql
3. run-sql.sh --env <env> --script test/contract/00_contract.sql
4. bin/run-endpoint-tests.sh --env <env>
5. npm run test:ci  (in app directory)
```

All steps must pass before a deployment is considered successful. Any non-zero exit halts the sequence.

---

## 7. What This Spec Does Not Cover

- End-to-end browser automation (out of scope for v1)
- Performance or load testing (out of scope for v1)
- Test data management beyond existing `95_data.sql` conventions
- CI pipeline orchestration (see CI/CD Pipeline Spec)
