# ORDS API Design Standards
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines the standards that every ORDS module in this framework must follow. It is the contract between the backend (Oracle ADB + ORDS) and the frontend (React). Consistency across all modules ensures that React clients, Codex, and future developers can predict the shape of any endpoint without reading its implementation.

---

## 2. Core Principles

1. **API-first, not schema-first.** The API is the public contract. The schema is an implementation detail and must never be visible to API consumers.
2. **Thin handlers, fat packages.** ORDS handler PL/SQL must be minimal — parameter extraction, package call, response emission only. All business logic lives in database packages.
3. **Adopt ORDS native shapes.** Collection responses use ORDS native pagination. Do not wrap or re-shape what ORDS provides for free.
4. **HTTP semantics matter.** Use correct HTTP status codes. Errors must be distinguishable by status code alone.
5. **Swagger must be useful.** Every module, template, and handler must be documented sufficiently for the auto-generated Swagger to serve as a working API reference.

---

## 3. URL Structure

### 3.1 Base Pattern

```text
/ords/<api_base_path>/api/v1/<resource>/
```

Where:

- `<api_base_path>` is the ORDS URL base path used for protected API delivery. It is a URL-facing identifier, not a database schema name.
- `api` is a fixed path segment present on all endpoints.
- `v1` is the API version prefix (see Section 4).
- `<resource>` is the resource name (see Section 3.2).

Example:

```text
/ords/road-api/api/v1/customers/
/ords/road-api/api/v1/order_items/
```

### 3.2 Resource Naming

- Lowercase plural nouns
- Underscores for multi-word resources (no hyphens — these cause issues in Oracle SQL contexts)
- No verbs in resource names — use HTTP methods to express actions

| ✅ Correct | ❌ Incorrect |
|---|---|
| `customers` | `customer` |
| `order_items` | `order-items` |
| `invoice_lines` | `getInvoiceLines` |

### 3.3 Sub-Resources

Hierarchical resources use nested paths:

```
/ords/myapp/api/v1/orders/{id}/lines/
```

Nesting must not exceed two levels. If a deeper path is required, reconsider the resource model.

### 3.4 Actions on Resources

Where a non-CRUD action is genuinely required, use a noun-based sub-resource rather than a verb:

```
/ords/myapp/api/v1/invoices/{id}/cancellation    ← POST to cancel
/ords/myapp/api/v1/invoices/{id}/approval        ← POST to approve
```

---

## 4. Versioning

### 4.1 Strategy

Versioning is URL-based. The version prefix `v1` is part of the base path for all endpoints.

The ORDS module base path must include the version:

```
/api/v1/
```

### 4.2 Version Increment Policy

- `v1` is the initial version
- Breaking changes require a new version (`v2`) — a new ORDS module with a new base path
- Non-breaking additions (new endpoints, new optional fields) do not require a version increment
- Both versions may coexist during a transition period
- Version retirement must be documented and communicated before removal

### 4.3 What Constitutes a Breaking Change

- Removing an endpoint
- Renaming or removing a response field
- Changing a field's data type
- Changing HTTP method or URL structure
- Making a previously optional parameter required

---

## 5. HTTP Method Semantics

| Method | Usage |
|---|---|
| `GET` | Retrieve a resource or collection. Must be read-only and idempotent. |
| `POST` | Create a new resource, or trigger an action. Not idempotent. |
| `PUT` | Replace a resource in full. Idempotent. |
| `PATCH` | Partial update of a resource. |
| `DELETE` | Remove a resource. Idempotent. |

Rules:

- `GET` handlers must never modify data
- `POST` is acceptable for complex queries that cannot be expressed as a `GET` (e.g. large filter sets), but this must be documented
- All methods may return a body except `DELETE`, which should return `204 No Content` on success

---

## 6. Response Shapes

### 6.1 Collection Responses

Collection responses must use ORDS native pagination shape. Do not re-wrap.

ORDS native shape:

```json
{
  "items": [ ... ],
  "hasMore": false,
  "limit": 25,
  "offset": 0,
  "count": 10,
  "links": [ ... ]
}
```

Pagination parameters are passed as query parameters:

```
GET /api/v1/customers/?offset=0&limit=25
```

### 6.2 Single Resource Responses

Single resource responses return the object directly, without an envelope:

```json
{
  "id": 123,
  "name": "Acme Ltd",
  "created_at": "2026-04-18T13:00:00Z"
}
```

### 6.3 Procedure / Action Responses

For `POST` actions that are not simple creates, return a minimal result object:

```json
{
  "id": 456,
  "status": "created"
}
```

or for actions without a created resource:

```json
{
  "status": "ok"
}
```

### 6.4 Field Conventions

- Field names: `snake_case`
- Dates and timestamps: ISO 8601 (`2026-04-18T13:00:00Z`)
- Null fields: included in the response with `null` value — do not omit
- Boolean fields: `true` / `false` (not `Y`/`N` or `1`/`0`)
- Number fields: unquoted JSON numbers (not strings)

---

## 7. Error Responses

### 7.1 Shape

All application-level errors must return a consistent JSON body with an appropriate HTTP status code:

```json
{
  "error": "NOT_FOUND",
  "message": "Customer with id 123 not found",
  "ora_code": "ORA-20001"
}
```

Fields:

| Field | Required | Description |
|---|---|---|
| `error` | Yes | Machine-readable error code, uppercase with underscores |
| `message` | Yes | Human-readable description safe to display or log |
| `ora_code` | No | ORA- error code where applicable |

### 7.2 HTTP Status Code Mapping

| Condition | HTTP Status |
|---|---|
| Success | 200 / 201 / 204 |
| Validation failure | 400 Bad Request |
| Unauthenticated | 401 Unauthorized |
| Insufficient privilege | 403 Forbidden |
| Resource not found | 404 Not Found |
| Business rule violation | 422 Unprocessable Entity |
| Unexpected server error | 500 Internal Server Error |

### 7.3 Error Emission from Handlers

Handlers emit errors by calling `owa_util.status_line` to set the HTTP status, then emitting the JSON body via `htp.p`. Known and unknown errors must follow `error-handling-contract-v1.md`. In particular:

- known application errors must be mapped through `error_api.handle_known`
- unknown server errors must be mapped through `error_api.handle_unknown`
- handlers must not concatenate `sqlerrm` or other internal details into the response body

Example handler pattern (see Section 9):

```sql
declare
  l_response    clob;
  l_status_code number;
begin
  customer_api.get_by_id(
    p_id          => :id,
    p_status_code => l_status_code,
    p_response    => l_response
  );
  owa_util.status_line(l_status_code);
  htp.p(l_response);
exception
  when others then
    if sqlcode between -20999 and -20000 then
      error_api.handle_known(
        p_sqlcode     => sqlcode,
        p_sqlerrm     => sqlerrm,
        p_status_code => l_status_code,
        p_response    => l_response
      );
    else
      error_api.handle_unknown(
        p_sqlerrm     => sqlerrm,
        p_backtrace   => dbms_utility.format_error_backtrace,
        p_context     => 'customers.get_by_id',
        p_status_code => l_status_code,
        p_response    => l_response
      );
    end if;
    owa_util.status_line(l_status_code);
    htp.p(l_response);
end;
```

The package procedure sets the status code and response body. The handler only passes them through.

---

## 8. Handler Contract

### 8.1 Thin Handler Rule

ORDS handler PL/SQL must contain only:

1. Bind variable extraction (ORDS bind variables to local variables)
2. A single package procedure call
3. Response emission (status code + body)
4. A top-level `WHEN OTHERS` exception handler as a last-resort safety net

No business logic, no SQL, no conditional branching, no string manipulation in handlers. If logic is needed, it belongs in the package.

### 8.2 Handler Template

```sql
declare
  l_response    clob;
  l_status_code number;
begin
  <package_name>.<procedure_name>(
    p_param_1     => :<bind_1>,
    p_status_code => l_status_code,
    p_response    => l_response
  );
  owa_util.status_line(l_status_code);
  htp.p(l_response);
exception
  when others then
    if sqlcode between -20999 and -20000 then
      error_api.handle_known(
        p_sqlcode     => sqlcode,
        p_sqlerrm     => sqlerrm,
        p_status_code => l_status_code,
        p_response    => l_response
      );
    else
      error_api.handle_unknown(
        p_sqlerrm     => sqlerrm,
        p_backtrace   => dbms_utility.format_error_backtrace,
        p_context     => '<module>.<handler>',
        p_status_code => l_status_code,
        p_response    => l_response
      );
    end if;
    owa_util.status_line(l_status_code);
    htp.p(l_response);
end;
```

### 8.3 Package Responsibility

The called package procedure is responsible for:

- All business logic
- All SQL
- Constructing the JSON response (using `json_object`, `json_array`, or `apex_json`)
- Setting the appropriate status code
- Raising application errors (`raise_application_error`) for known error conditions

---

## 9. Swagger / OpenAPI Standards

ORDS auto-generates an OpenAPI document from module metadata. To make this useful:

### 9.1 Module

- Every module must have a description stating its purpose and the resource it owns

### 9.2 Templates

- Every template must have a description stating what resource or sub-resource it represents

### 9.3 Handlers

- Every handler must have a description stating what the operation does
- All bind parameters must be described
- Expected response codes must be listed in the handler comments

### 9.4 What Not to Over-Document

Handler documentation should be concise — one sentence per handler is sufficient. The goal is a Swagger that is navigable and useful, not exhaustive prose.

---

## 10. ORDS Module Structure

Each module maps to a directory under `api/modules/`:

```
api/modules/<module_name>/
  module.create.sql
  module.drop.sql
  privileges.create.sql
  privileges.drop.sql
```

Module naming convention: `<resource>` (matches the URL resource segment).

Examples:

```
api/modules/customers/
api/modules/order_items/
```

Each module owns one resource. If a module grows to cover multiple unrelated resources, split it.

---

## 11. What This Spec Does Not Cover

- Authentication and authorisation (see `authentication-spec-v1.md`)
- Public UI asset delivery and upload tooling (see `file-upload-and-ui-delivery-spec-v1.md`)
- ORDS security configuration and privilege management (see `ords-security-configuration-v1.md`)
- How the React client consumes these endpoints (see `react-project-structure-conventions-v1.md`)
