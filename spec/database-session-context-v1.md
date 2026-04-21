# Database Session Context
**Version:** 1.0  
**Status:** Draft

---

## 1. Purpose

This document defines the intended ROAD contract for exposing authenticated request identity to PL/SQL and database policy logic after ORDS has accepted a request.

It describes the target session-context interface for application code, even where the underlying implementation is not yet fully standardised across all supported authentication provider profiles.

---

## 2. Status of This Spec

This is a contract-first v1 document.

It defines the target behavioural interface for ROAD, but the current source implementations reviewed for ROAD do not yet provide one complete, standardised session-context solution across all auth profiles.

For that reason:

- the contract in this spec is normative
- the concrete implementation details remain partially open in v1

---

## 3. Core Principles

1. **Authentication and session context are separate concerns.** Token issuance or validation alone does not define the application session context used by business PL/SQL.
2. **Business packages need a stable caller identity interface.** Application code must not parse raw JWTs repeatedly.
3. **Context setup must be centralised.** ROAD must not duplicate request-identity extraction logic across handlers and business packages.
4. **Context failure is a real failure.** If a protected request is accepted by ORDS but ROAD cannot establish the required session context, the request must fail clearly.
5. **Authorisation layers may stack.** ORDS privilege checks are the first gate; finer-grained data rules may depend on the established session context.

---

## 4. Scope

This spec covers:

- the target application-context contract for PL/SQL
- what business logic should be able to read about the current caller
- where session-context setup belongs conceptually
- interaction with error logging and downstream authorisation

This spec does not cover:

- token issuance or validation mechanics (see `authentication-spec-v1.md`)
- ORDS privilege or JWT profile DDL details (see `ords-security-configuration-v1.md`)
- full VPD policy design
- user lifecycle and provisioning models

---

## 5. Problem Statement

ROAD applications need more than a binary authenticated/not-authenticated outcome.

After ORDS has accepted a protected request, business PL/SQL commonly needs to know:

- who the caller is
- what auth profile or issuer authenticated them
- what scopes or privileges they hold
- what audit identity should be recorded

The source implementations reviewed for ROAD demonstrate token issuance and token validation patterns, but they do not yet yield one proven framework-wide standard for propagating that identity into a reusable Oracle session context.

---

## 6. Target ROAD Session-Context Contract

For an authenticated protected request, ROAD business PL/SQL should be able to obtain, at minimum:

| Value | Meaning |
|---|---|
| principal identifier | Stable caller identity, typically derived from `sub` or equivalent |
| issuer/profile name | Which auth profile accepted the request |
| audience/resource id | Intended protected resource identifier |
| granted scopes or effective privileges | The privileges available to the caller |
| authenticated flag | Whether a valid ROAD auth context exists |
| correlation id | Request correlation identifier where available |

For unauthenticated or public requests, the context contract must still behave predictably and return a safe unauthenticated state.

---

## 7. PL/SQL Access Pattern

### 7.1 Central Accessor Package

ROAD should expose a central accessor package or equivalent utility layer for session context.

Illustrative interface:

```sql
procedure assert_authenticated;
function is_authenticated return boolean;
function get_principal return varchar2;
function get_issuer return varchar2;
function get_audience return varchar2;
function get_scopes return varchar2;
```

### 7.2 No Direct JWT Parsing in Business Packages

Business packages must not:

- parse bearer tokens directly
- decode JWT payloads directly
- depend on ad hoc `SYS_CONTEXT` key strings scattered through application code

### 7.3 Stable Interface

The session-context access pattern must remain stable across auth provider profiles.

---

## 8. Context Sources

Depending on the selected auth profile, the effective caller identity may originate from:

- ORDS-native OAuth context
- externally issued JWT claims validated by ORDS
- locally issued scaffold JWT claims validated by ORDS

ROAD must present those through one consistent application-facing session-context contract, even if the extraction mechanism differs underneath.

---

## 9. Context Establishment Strategies

The following are architectural strategies available to ROAD. The exact v1 implementation is not yet standardised.

### 9.1 ORDS-Provided Request Context

Where ORDS exposes reliable request or authentication metadata to PL/SQL, ROAD may normalise that into the framework session context.

### 9.2 Application Context Package

ROAD may establish an Oracle application context and populate it through a central package before business logic executes.

### 9.3 Request Bootstrap Layer

ROAD may introduce a request bootstrap step that:

- reads the effective request identity
- validates the minimum required fields for business use
- exposes them through the session-context API

### 9.4 Prohibited Pattern

ROAD must not require every package procedure to rediscover or reinterpret request identity independently.

---

## 10. Minimum Behavioural Contract

Regardless of implementation strategy, ROAD must satisfy the following rules.

### 10.1 Authenticated Protected Request

If ORDS accepts a protected request, ROAD must expose a stable authenticated principal to business code before business logic depends on it.

### 10.2 Public Request

Public requests may have no authenticated principal, but the context API must still return a predictable unauthenticated state.

### 10.3 Context Establishment Failure

If a request is authenticated at the ORDS level but ROAD cannot establish the required session context, the request must fail explicitly rather than falling back to an ambiguous anonymous state.

### 10.4 Logging Compatibility

The effective principal should be available to logging and diagnostics where possible.

---

## 11. Interaction with Error Handling

### 11.1 Error Logging

Where session context is available, error logging should record the effective principal or equivalent caller identity in addition to the database session user.

### 11.2 Known vs Unknown Errors

Session-context establishment failures are framework or infrastructure failures, not ordinary business validation failures. They must therefore be treated as server-side errors unless a clearer framework-specific error classification is introduced later.

### 11.3 No Silent Degradation

ROAD must not silently downgrade an authenticated request to anonymous processing if session-context setup fails.

---

## 12. Interaction with Authorisation

### 12.1 First Gate: ORDS Privileges

ORDS privilege enforcement remains the first authorisation gate for protected endpoints.

### 12.2 Second Gate: Application Rules

Once session context is established, business PL/SQL may use it for:

- row filtering
- business rule checks
- audit attribution
- optional VPD integration

### 12.3 VPD in v1

VPD and row-level security integration are optional in v1 and are not fully standardised by the current source implementations.

---

## 13. Implementation Status by Provider

| Profile | Session-Context Contract Target | Implementation Status in Reviewed Sources |
|---|---|---|
| `external_oidc` | Supported conceptually | Not fully standardised in source repos |
| `ords_oauth` | Supported conceptually | Not fully standardised in source repos |
| `ords_local_jwt_scaffold` | Supported conceptually | Not fully standardised in source repos |

The reviewed source repositories demonstrate auth issuance and validation patterns, but do not yet provide one framework-ready, reusable session-context implementation that ROAD can adopt unchanged.

---

## 14. Open Questions

The following questions remain open for a later revision:

1. Which ORDS or ADB request metadata is reliably available to PL/SQL across all ROAD deployment modes?
2. Should ROAD standardise an Oracle application-context namespace and key set in v1 or v2?
3. Should scope lists be normalised into the session context at request start?
4. What is the precise handoff point between ORDS-authenticated request handling and business package execution?
5. What is the standard VPD integration pattern, if any?

---

## 15. What This Spec Does Not Cover

- JWT issuance or login flows (see `authentication-spec-v1.md`)
- ORDS privilege and trust configuration (see `ords-security-configuration-v1.md`)
- frontend auth state management (see `react-project-structure-conventions-v1.md`)
- external identity-provider setup

---

## 16. Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-04-21 | Initial contract-first draft based on reviewed auth source implementations; implementation details remain partially open |
