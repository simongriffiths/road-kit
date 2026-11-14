# Error Handling Contract
**Version:** 2.0  
**Status:** Approved

**Changed in 2.0** (`planning/spec-patch-12-business-decisions-and-decision-record.md`, road-atlas
ledger D-05): a business rule that rejects a proposal is no longer an error. It returns HTTP 200
with a structured outcome and a decision record. HTTP 422 is no longer used. The error code
mapping in section 4.1 now matches `error_api`.

---

## 1. Purpose

This document defines how errors flow from Oracle through ORDS to the React client. It covers server-side error classification, logging, response emission, and client-side handling conventions. It is the complement to the ORDS API Design Standards — that spec defines error response *shape*, this spec defines error *behaviour*.

---

## 2. Core Principles

1. **Errors are first-class.** Every layer must handle errors explicitly. Silent failures are not permitted.
2. **Known errors are informative.** Validation, permission and lookup errors surface a safe, human-readable message.
3. **A business decision is not an error.** When a governed action's decision code runs and rejects a proposal, the rejection is a result, returned with HTTP 200 (section 3.2).
4. **Unknown errors are opaque to the client.** Unexpected server errors return a generic message. Detail goes to the error log, not the response.
5. **The client never parses ORA- codes.** HTTP status is the primary signal. The `error` field is the secondary signal. Raw Oracle error codes are for diagnostics only.
6. **Logging is non-blocking.** Error log writes use autonomous transactions and must never cause a secondary failure.

---

## 3. Error Classification

Every response falls into one of three classes. The dividing line is whether the decision code of a governed action ran. This follows section 5.4 of the Governed Surface Contract definition.

| Class | When it applies | HTTP | Section |
|---|---|---|---|
| The system failed | No decision could be reached | 5xx, or no response | 3.3 |
| The call was wrong | The request was stopped before any decision code ran | 4xx | 3.1 |
| The business decided | The decision code ran and accepted or rejected the proposal | 200 | 3.2 |

### 3.1 Known Errors (4xx): the call was wrong

Errors that are anticipated, have a defined cause, and can produce a safe message for the client.

| HTTP Status | Meaning | Example |
|---|---|---|
| 400 | Invalid input or malformed request | Missing required parameter |
| 401 | Unauthenticated | JWT missing or expired |
| 403 | Insufficient privilege | User lacks the permission the endpoint requires |
| 404 | Resource not found, on a read | Customer id does not exist |
| 409 | Stale write on an endpoint that is not a governed action | Read token older than the record |

A permission that depends only on the principal, and not on the state of any record, may be checked before the decision code runs; failing it is a 403. A rule that depends on state is a business decision (section 3.2), even when it is about access.

For known errors:
- The `message` field is safe to display to the end user
- The `error` code is machine-readable and stable
- No stack trace or internal detail is included in the response

### 3.2 Business Decisions (200)

A governed action decides a proposal: it re-reads current state, tests its rules, and either applies the change or refuses it. Both answers are results, and both return HTTP 200 with an **outcome**:

```json
{
  "contract_version": "1.0.0",
  "decision": "rejected",
  "rejections": [
    {
      "rule_id": "ITEM_ALREADY_CLAIMED",
      "message": "Another principal holds a claim on this item until 11:42.",
      "retryable": true,
      "ids": [42]
    }
  ],
  "audit_id": 91878
}
```

An accepted outcome carries `"decision": "accepted"` and a `result` object instead of `rejections`. Every outcome carries `contract_version` and `audit_id`, the id of the decision record.

Each rejection has a stable `rule_id`, a `message` safe to show, `retryable`, and where disclosure is permitted the `ids` of the records involved. `retryable: true` means the same proposal could succeed later, or after the consumer re-reads state. Examples of business decisions: a stale read token on a governed action, a lock held by someone else, a state transition that is not allowed, a caller who is no longer a contributor.

Every decision is recorded in `road_decisions`. An accepted decision is recorded in the same transaction as the change. A rejected decision rolls back its changes and is recorded in an autonomous transaction, so the record survives the rollback. See section 4.4.

### 3.3 Unknown Errors (5xx)

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

All packages must use `raise_application_error` for known errors (section 3.1), using the reserved range `-20000` to `-20999`. Business rejections are never raised (section 4.4).

`error_api` holds the fixed mapping. Each code is listed explicitly:

| Code | `error` | HTTP | Raised by |
|---|---|---|---|
| `-20001` | `VALIDATION_ERROR` | 400 | Packages, for malformed input |
| `-20004` | `NOT_FOUND` | 404 | Packages, for an unknown resource on a read |
| `-20009` | `CONFLICT` | 409 | Packages, for a stale write on an endpoint that is not a governed action |
| `-20403` | `FORBIDDEN` | 403 | `road_ctx_pkg.require_permission` and `require_role` (`road_ctx_pkg.c_forbidden`) |
| `-8601` | `FORBIDDEN` | 403 | A SQL assertion violation, as defence in depth |

`-20002` and `-20003` are not used. `-20003` mapped a business rule to 422 before version 2.0. Any code in the reserved range that is not in this table is treated as a coding mistake: it is logged to `error_log` and returned as a 500.

Packages raise known errors explicitly:

```sql
c_not_found constant number := -20004;

if l_count = 0 then
  raise_application_error(c_not_found, 'Customer with id ' || p_id || ' not found');
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

### 4.4 Governed Actions Return Outcomes

A governed action's package function returns its outcome as JSON. It does not raise for a business rejection. `road_decision_api` writes the decision record and builds the outcome, so every action returns the same shape:

| Call | Transaction | Returns |
|---|---|---|
| `road_decision_api.accept` | The caller's | An accepted outcome |
| `road_decision_api.reject` | Autonomous. The caller rolls back its own changes first | A rejected outcome |
| `road_decision_api.reject_undisclosed` | Autonomous | An accepted outcome, while the record holds the true rejection. Only for an action whose contract declares a non-disclosing outcome |
| `road_decision_api.prior_outcome` | Read only | The earlier outcome for a repeated idempotency key, or null |

The handler sends the outcome with status 200. Its exception block is unchanged and still handles wrong calls and unknown errors:

```sql
declare
  l_outcome     json;
  l_response    clob;
  l_status_code number;
begin
  l_outcome := item_api.request_claim(json(:body_text));
  owa_util.status_line(200);
  htp.p(json_serialize(l_outcome));
exception
  when others then
    -- as section 4.3
end;
```

The package specification of `road_decision_api` shows the full decision procedure, including idempotent replay and the race between two copies of one proposal.

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

Business decisions (200) are not logged to `error_log` either. They are recorded in `road_decisions` (section 4.4).

---

## 6. Client-Side Error Handling

### 6.1 Global Error Handler

All ORDS API calls must be made through a central fetch wrapper. The wrapper is responsible for:

- Detecting non-2xx HTTP responses
- Returning a 200 outcome to the caller unchanged, whether its `decision` is `accepted` or `rejected`
- Parsing the JSON error body
- Classifying the error (known 4xx vs unknown 5xx vs network failure)
- Dispatching to the global notification system

Individual components must not implement their own error handling for API failures. They call the fetch wrapper and handle the success case only.

A rejected outcome is not an API failure. The component that made the proposal shows each rejection's `message` where the user acted, and decides what to offer next from `retryable`. The wrapper must not turn a rejected outcome into an error or a toast.

### 6.2 Error Classification on the Client

| Condition | Classification | UI Behaviour |
|---|---|---|
| 200, `decision: rejected` | Business decision | Returned to the proposing component, which shows the rejections |
| 400 | Known — validation | Toast notification, show `message` |
| 401 | Authentication | Redirect to login |
| 403 | Authorisation | Toast notification, generic "not permitted" |
| 404 | Not found | Toast notification, show `message` |
| 409 | Conflict | Toast notification, show `message` |
| 500 | Unknown server error | Error banner, generic message |
| Network failure / no response | Network error | Error banner, "Unable to reach server" |

### 6.3 Notification Components

**Toast** (non-blocking)

Used for: 400, 403, 404, 409

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
| Validation failure | `raise_application_error(-20001, ...)` | `handle_known` | 400 | Toast with message |
| Business rule rejects a proposal | `road_decision_api.reject` returns an outcome | Normal return | 200 | Proposing component shows the rejections |
| Record not found on a read | `raise_application_error(-20004, ...)` | `handle_known` | 404 | Toast with message |
| Unexpected ORA- error | Unhandled exception | `handle_unknown` + log | 500 | Error banner |
| JWT expired | Auth middleware | ORDS 401 | 401 | Redirect to login |
| Network timeout | — | — | None | Error banner |

---

## 8. What This Spec Does Not Cover

- JWT validation and authentication flow (see `authentication-spec-v1.md`)
- Specific error codes per package (defined in each package spec)
- Frontend component implementation details (see `react-project-structure-conventions-v1.md`)
- ORDS privilege errors (see `ords-security-configuration-v1.md`)
