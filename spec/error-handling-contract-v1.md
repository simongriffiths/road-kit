# Error Handling Contract
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines how errors flow from Oracle through ORDS to the React client. It covers server-side error classification, logging, response emission, and client-side handling conventions. It is the complement to the ORDS API Design Standards — that spec defines error response *shape*, this spec defines error *behaviour*.

---

## 2. Core Principles

1. **Errors are first-class.** Every layer must handle errors explicitly. Silent failures are not permitted.
2. **Known errors are informative.** Business and validation errors surface a safe, human-readable message.
3. **Unknown errors are opaque to the client.** Unexpected server errors return a generic message. Detail goes to the error log, not the response.
4. **The client never parses ORA- codes.** HTTP status is the primary signal. The `error` field is the secondary signal. Raw Oracle error codes are for diagnostics only.
5. **Logging is non-blocking.** Error log writes use autonomous transactions and must never cause a secondary failure.

---

## 3. Error Classification

### 3.1 Known Errors (4xx)

Errors that are anticipated, have a defined cause, and can produce a safe message for the client.

| HTTP Status | Meaning | Example |
|---|---|---|
| 400 | Invalid input or malformed request | Missing required parameter |
| 401 | Unauthenticated | JWT missing or expired |
| 403 | Insufficient privilege | User lacks required role |
| 404 | Resource not found | Customer id does not exist |
| 422 | Business rule violation | Cannot cancel a shipped order |

For known errors:
- The `message` field is safe to display to the end user
- The `error` code is machine-readable and stable
- No stack trace or internal detail is included in the response

### 3.2 Unknown Errors (5xx)

Errors that are not anticipated — unexpected exceptions, unhandled ORA- codes, infrastructure failures.

| HTTP Status | Meaning |
|---|---|
| 500 | Unexpected server error |

For unknown errors:
- The response message is always generic: `"An unexpected error occurred"`
- Full detail (SQLERRM, SQLCODE, backtrace) is written to the error log
- No internal detail is exposed in the response

---

## 4. Server-Side Error Handling

### 4.1 Package Error Convention

All packages must use `raise_application_error` for known errors, using the reserved range `-20000` to `-20999`.

Applications should define a fixed mapping of error codes to HTTP status and `error` string:

```sql
-- known error codes
c_err_not_found       constant number := -20001;
c_err_validation      constant number := -20002;
c_err_business_rule   constant number := -20003;
c_err_forbidden       constant number := -20004;
```

Packages raise known errors explicitly:

```sql
if l_count = 0 then
  raise_application_error(c_err_not_found, 'Customer with id ' || p_id || ' not found');
end if;
```

### 4.2 Error Mapping Package

A shared utility package `error_api` must be responsible for:

- Mapping `raise_application_error` codes to HTTP status codes
- Constructing the standard JSON error response
- Writing to the error log for unknown errors

```sql
-- error_api.pks
procedure handle_known(
  p_sqlcode     in number,
  p_sqlerrm     in varchar2,
  p_status_code out number,
  p_response    out clob
);

procedure handle_unknown(
  p_sqlerrm     in varchar2,
  p_backtrace   in varchar2,
  p_context     in varchar2 default null,
  p_status_code out number,
  p_response    out clob
);
```

### 4.3 Handler Exception Pattern

Every ORDS handler must follow this exception structure:

```sql
declare
  l_response    clob;
  l_status_code number;
begin
  <package_name>.<procedure>(
    p_param       => :<bind>,
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

---

## 5. Error Log

### 5.1 Table Definition

```sql
create table error_log (
  id            number         generated always as identity primary key,
  error_time    timestamp      default systimestamp not null,
  sqlcode       number,
  sqlerrm       varchar2(4000),
  backtrace     clob,
  context       varchar2(500),
  session_user  varchar2(128)  default sys_context('userenv','session_user')
);
```

### 5.2 Write Convention

All writes to `error_log` must use an autonomous transaction so that a logging failure cannot cause a rollback of the main transaction, and so that the log entry is committed even if the main transaction rolls back:

```sql
procedure write_error_log(
  p_sqlcode   in number,
  p_sqlerrm   in varchar2,
  p_backtrace in varchar2,
  p_context   in varchar2
) is
  pragma autonomous_transaction;
begin
  insert into error_log (sqlcode, sqlerrm, backtrace, context)
  values (p_sqlcode, p_sqlerrm, p_backtrace, p_context);
  commit;
exception
  when others then
    null; -- logging must never cause a secondary failure
end;
```

### 5.3 What Is Logged

Unknown errors (5xx) always log:

- `sqlcode`
- `sqlerrm`
- `dbms_utility.format_error_backtrace`
- Handler context string (module + handler name)
- Session user

Known errors (4xx) are not logged to `error_log`. They are expected conditions.

---

## 6. Client-Side Error Handling

### 6.1 Global Error Handler

All ORDS API calls must be made through a central fetch wrapper. The wrapper is responsible for:

- Detecting non-2xx HTTP responses
- Parsing the JSON error body
- Classifying the error (known 4xx vs unknown 5xx vs network failure)
- Dispatching to the global notification system

Individual components must not implement their own error handling for API failures. They call the fetch wrapper and handle the success case only.

### 6.2 Error Classification on the Client

| Condition | Classification | UI Behaviour |
|---|---|---|
| 400, 422 | Known — validation/business | Toast notification, show `message` |
| 401 | Authentication | Redirect to login |
| 403 | Authorisation | Toast notification, generic "not permitted" |
| 404 | Not found | Toast notification, show `message` |
| 500 | Unknown server error | Error banner, generic message |
| Network failure / no response | Network error | Error banner, "Unable to reach server" |

### 6.3 Notification Components

**Toast** (non-blocking)

Used for: 400, 403, 404, 422

- Appears in a fixed corner of the viewport
- Disappears automatically after 4 seconds
- May be dismissed manually
- Shows the `message` field from the error response for known errors
- Queue-safe — multiple toasts may be visible simultaneously

**Error Banner** (persistent)

Used for: 500, network failures

- Appears at the top of the page content area
- Requires explicit dismissal
- Always shows a generic message — never exposes server detail
- Only one banner visible at a time — subsequent errors replace it

### 6.4 Fetch Wrapper Contract

The fetch wrapper must:

- Accept the same arguments as `fetch` (URL, options)
- Return the parsed response body on success
- Throw a typed error object on failure containing: `status`, `error`, `message`
- Never return a response object directly to the caller
- Handle JSON parse failures on error responses gracefully (fall back to generic message)

Example typed error:

```typescript
interface ApiError {
  status: number;
  error: string;
  message: string;
}
```

### 6.5 401 Handling

On a 401 response:

- The fetch wrapper must clear the stored JWT
- Redirect to the login page
- Not show a toast or banner — the redirect is the signal

---

## 7. Error Scenarios Reference

| Scenario | Oracle | ORDS Handler | HTTP Status | Client Behaviour |
|---|---|---|---|---|
| Record not found | `raise_application_error(-20001, ...)` | `handle_known` | 404 | Toast with message |
| Validation failure | `raise_application_error(-20002, ...)` | `handle_known` | 400 | Toast with message |
| Business rule violation | `raise_application_error(-20003, ...)` | `handle_known` | 422 | Toast with message |
| Unexpected ORA- error | Unhandled exception | `handle_unknown` + log | 500 | Error banner |
| JWT expired | Auth middleware | ORDS 401 | 401 | Redirect to login |
| Network timeout | — | — | None | Error banner |

---

## 8. What This Spec Does Not Cover

- JWT validation and authentication flow (see `authentication-spec-v1.md`)
- Specific error codes per package (defined in each package spec)
- Frontend component implementation details (see `react-project-structure-conventions-v1.md`)
- ORDS privilege errors (see `ords-security-configuration-v1.md`)
