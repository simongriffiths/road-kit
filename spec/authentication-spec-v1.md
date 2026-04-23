# Authentication
**Version:** 1.0  
**Status:** Draft

---

## 1. Purpose

This document defines the authentication contract for applications built on this framework. It standardises the application-facing authentication model used by React, ORDS, and testing tooling, while allowing multiple authentication provider profiles behind that contract.

The goal is one framework-level authentication interface with provider-specific implementation details isolated behind it.

---

## 2. Core Principles

1. **One application contract, multiple auth backends.** ROAD applications must not fork their frontend architecture based on the chosen authentication provider.
2. **Bearer token transport is standard.** Protected API access always uses `Authorization: Bearer <token>`.
3. **ORDS is always the resource server.** Regardless of who issues the token, protected ROAD endpoints are enforced by ORDS privileges.
4. **Authentication and authorisation are distinct.** A valid token proves identity. ORDS privileges and downstream rules decide access.
5. **ORDS-boundary rejection is normalised to 401 in v1.** In the ORDS-first ROAD profile, missing authentication and ORDS privilege rejection both surface as `401 Unauthorized`. `403 Forbidden` is reserved for downstream application-level authorization if ROAD later chooses to distinguish it inside handler or package logic after ORDS has already admitted the request.
6. **Provider-specific differences must not leak into feature code.** React pages, hooks, and feature components must consume a stable auth interface.

---

## 3. Scope

This spec covers:

- token acquisition patterns
- token transport to protected endpoints
- token lifecycle expectations in React
- required JWT claims used by ROAD
- ORDS-facing protected endpoint expectations
- supported authentication provider profiles

This spec does not cover:

- ORDS privilege DDL details (see `ords-security-configuration-v1.md`)
- schema-level JWT profile DDL details (see `ords-security-configuration-v1.md`)
- Oracle session context propagation details (see `database-session-context-v1.md`)
- frontend page/component implementation details beyond the auth contract (see `react-project-structure-conventions-v1.md`)

---

## 4. Common ROAD Authentication Contract

### 4.1 Bearer Token Transport

All protected API requests must send a bearer token in the HTTP `Authorization` header:

```http
Authorization: Bearer <token>
```

ROAD applications must not send access tokens in query parameters or custom headers.

### 4.2 Protected Endpoint Behaviour

Protected endpoints must be enforced by ORDS privilege configuration. Handlers and business packages must not implement ad hoc token gatekeeping logic.

### 4.3 Unauthenticated vs Forbidden

Protected ROAD endpoints must follow this status model:

| Condition | HTTP Status |
|---|---|
| Missing token | 401 |
| Invalid token | 401 |
| Expired token | 401 |
| Wrong issuer / audience / signature | 401 |
| Valid token but missing required privilege / scope | 401 at the ORDS boundary in the v1 ORDS-first profile |

### 4.4 Token Storage Rules

React applications must store the active token in `sessionStorage` through `src/utils/auth.ts` only, as already defined in `react-project-structure-conventions-v1.md`.

`localStorage` must not be used for ROAD access tokens in v1.

### 4.5 Login and Logout Contract

The login mechanism may vary by provider profile, but the application-facing result must be the same:

- successful login produces an access token
- the token is stored through the auth utility layer
- auth state is updated through `AuthContext`
- protected API requests use that token automatically

Logout must:

- clear the stored token
- update auth state
- redirect or navigate to the login route where applicable

### 4.6 Expiration Handling

When a protected API call returns `401`:

- the stored token must be cleared
- the user must be treated as signed out
- the client must redirect to the login route
- no toast or error banner is shown for the `401` itself

This matches the behaviour defined in `error-handling-contract-v1.md`.

---

## 5. React Client Contract

### 5.1 AuthContext

`AuthContext` is the single source of truth for authentication state. Components must not inspect JWTs directly.

### 5.2 useAuth Hook

All components and hooks that need auth state must consume `useAuth()` rather than touching storage directly.

### 5.3 API Client Responsibilities

The central API client must:

- attach the bearer token when present
- detect `401` responses
- clear auth state and redirect on `401`
- surface `403` responses as normal known errors

### 5.4 Protected Routes

Routes requiring authentication must be guarded through a dedicated route wrapper or equivalent pattern defined by the React conventions spec.

### 5.5 Provider Isolation

Feature pages and data hooks must not contain provider-specific code such as:

- direct Auth0 token requests
- direct ORDS `/oauth/token` calls
- direct JWT parsing for authorization decisions

Provider-specific mechanics belong in auth services, auth hooks, or the authentication shell around the app.

---

## 6. JWT Claims Contract

Where the provider profile uses JWT access tokens, ROAD standardises the following claim expectations.

### 6.1 Required Claims

| Claim | Requirement | Purpose |
|---|---|---|
| `iss` | Required | Token issuer identifier |
| `aud` | Required | Intended resource audience |
| `sub` | Required | Authenticated principal identifier |
| `exp` | Required | Expiration time |
| `iat` | Required | Issued-at time |

### 6.2 Authorisation Claims

At least one of the following claim shapes must support ROAD authorisation:

| Claim | Usage |
|---|---|
| `scope` | Space-delimited scope / privilege names |
| `scp` | Alternate scope claim supported by the provider |

The default ROAD pattern is scope-based ORDS authorisation. Protected resources expect the token to carry the relevant ORDS privilege name in `scope` or `scp`.

### 6.3 Header Fields

Where JWT signing uses asymmetric keys, the token header should include:

- `alg`
- `typ`
- `kid` where applicable

### 6.4 Claim Stability

ROAD feature code may rely on:

- `sub`
- `iss`
- `aud`
- `exp`
- `iat`
- `scope` or `scp`

ROAD feature code must not rely on provider-specific claims unless the application explicitly documents that dependency.

---

## 7. Authorisation Model

### 7.1 ORDS Privilege Gate

ORDS privileges are the first authorisation gate for protected endpoints.

### 7.2 Scope-Based Default

The ROAD default is scope-based authorisation:

- the ORDS privilege name is stable
- the token contains that privilege name in `scope` or `scp`
- ORDS allows access only when both token validation and privilege expectations are satisfied

### 7.3 Role-Based Variant

Role-based JWT authorisation is supported where a valid role claim is mapped to ORDS roles. This is a variant, not the default baseline.

### 7.4 Downstream Rules

Further application-specific authorisation may exist in PL/SQL, but it must not replace the ORDS privilege gate for protected endpoints.

---

## 8. Supported Provider Profiles

| Profile | Token Issuer | Validation Mode | Intended Usage | Production Suitability |
|---|---|---|---|---|
| `external_oidc` | External OIDC provider such as Auth0 | ORDS JWT profile + JWKS | Standard production pattern | Yes |
| `ords_oauth` | ORDS | ORDS-native OAuth validation | ORDS-native deployments | Yes, with current ORDS APIs |
| `ords_local_jwt_scaffold` | PL/SQL/ORDS scaffold inside the app schema | ORDS JWT profile + local JWKS | Development and demonstration only | No |

---

## 9. Provider Profile: `external_oidc`

This profile is based on the working Auth0 + ORDS companion implementation.

### 9.1 Flow Summary

1. The client requests an access token from the external IdP.
2. The IdP issues an RS256-signed JWT access token.
3. The client calls the protected ORDS endpoint with that token.
4. ORDS validates issuer, audience, and signature using the configured JWKS URL.
5. ORDS enforces the protected privilege before allowing access to the handler.

### 9.2 Required Configuration Values

The validation contract depends on exact alignment of:

- issuer
- audience
- JWKS URL

These values must match the token and provider configuration exactly.

### 9.3 Audience Rule

The audience is a logical resource identifier. It is not required to equal the ORDS endpoint URL.

### 9.4 Scope Rule

For scope-based JWT profiles, the token `scope` or `scp` claim must contain the ORDS privilege name protecting the requested resource.

### 9.5 Failure Modes

Typical failures include:

- wrong issuer
- wrong audience
- unreachable JWKS
- invalid signature
- missing required scope

These must surface according to Section 4.3. In the v1 ORDS-first profile, missing required scope also returns `401`.

### 9.6 ROAD Recommendation

`external_oidc` is the preferred production profile for ROAD.

---

## 10. Provider Profile: `ords_oauth`

This profile is based on the working ORDS-native OAuth prototype in `oauthords/TestCase01`.

### 10.1 Flow Summary

ORDS itself issues tokens and protects endpoints through its OAuth model.

### 10.2 Supported Grant Types

The prototype demonstrates:

- `client_credentials`
- `authorization_code`

Both are compatible with ROAD in principle, provided the application-facing contract remains stable.

### 10.3 ORDS Token Endpoints

The prototype uses the standard ORDS OAuth endpoints for token issuance and authorisation.

### 10.4 Application Contract

Even when ORDS issues the token:

- the client still stores and sends a bearer token
- protected API requests still use the same auth client pattern
- protected endpoint rejection semantics remain those defined in Section 4.3

### 10.5 Modernization Note

The source prototype uses older `OAUTH` package examples. New ROAD documentation and examples should prefer current ORDS-supported package names and APIs where available, while preserving the same behavioural model.

---

## 11. Provider Profile: `ords_local_jwt_scaffold`

This profile is based on the working JWT scaffold prototype in `oauthords/TestCase02`.

### 11.1 Intended Usage

This profile is for development and demonstration use only.

It must not be presented as the primary production authentication pattern for ROAD.

### 11.2 Flow Summary

1. Client posts username/password to a login endpoint hosted in ORDS.
2. PL/SQL validates the credentials.
3. PL/SQL constructs and signs an RS256 JWT.
4. A public ORDS JWKS endpoint exposes the matching public key.
5. ORDS validates returned bearer tokens through a schema-level JWT profile.

### 11.3 Required Characteristics

This profile must include:

- a public login endpoint
- a public JWKS endpoint
- a schema-level JWT profile
- a stable issuer / audience / scope contract

### 11.4 Key Rotation

Key rotation must update the active signing key and JWKS representation. Callers must tolerate a short transition window while ORDS refreshes its cached JWKS.

### 11.5 Restriction

Hardcoded users, locally managed signing keys, or similar scaffold mechanics must remain clearly marked as development-only.

---

## 12. Testing Requirements

Every ROAD auth profile must be testable at the HTTP level.

Minimum required tests:

| Test Case | Expected Status |
|---|---|
| Protected endpoint without token | 401 |
| Login / token acquisition happy path | 200 |
| Protected endpoint with valid token | 200 |
| Invalid token | 401 |
| Expired token | 401 |
| Wrong issuer or audience | 401 |
| Missing required scope / privilege | 401 in the v1 ORDS-first profile |

Where the provider supports key rotation or JWKS refresh behaviour, additional tests should verify that behaviour explicitly.

---

## 13. Conformance Rules

A ROAD authentication provider is conformant only if:

1. React feature code remains provider-agnostic.
2. Protected endpoints are enforced by ORDS privileges.
3. Protected requests use bearer token transport.
4. ORDS-boundary auth and privilege rejection behaviour matches this spec.
5. The token or equivalent auth artifact exposes the claims required by ROAD.

---

## 14. What This Spec Does Not Cover

- ORDS privilege deployment mechanics (see `ords-security-configuration-v1.md`)
- JWT profile DDL and deployment details (see `ords-security-configuration-v1.md`)
- Oracle session context propagation (see `database-session-context-v1.md`)
- frontend screen implementation details (see `react-project-structure-conventions-v1.md`)

---

## 15. Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-04-21 | Initial draft based on external OIDC, ORDS OAuth, and ORDS local JWT scaffold source implementations |
