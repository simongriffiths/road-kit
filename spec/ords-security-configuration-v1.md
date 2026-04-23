# ORDS Security Configuration
**Version:** 1.0  
**Status:** Draft

---

## 1. Purpose

This document defines how ORDS security configuration is managed as code in ROAD applications. It standardises privileges, optional roles, module protection, and JWT trust configuration so that security behaviour is explicit, versioned, and deployable through the SQL runner framework.

---

## 2. Core Principles

1. **Security is code.** ORDS privileges and trust configuration must be versioned and deployed through SQL artifacts.
2. **Privileges protect resources.** Handlers must not implement bespoke access control in place of ORDS protection.
3. **Scope-based protection is the ROAD default.** The default authorisation pattern is token scope aligned with ORDS privilege names.
4. **JWT trust configuration must match exactly.** Issuer, audience, and JWKS settings must align character-for-character with the token issuer.
5. **Configuration mode must be explicit.** ROAD deployments must state whether JWT trust is configured at schema level or pool level.

---

## 3. Scope

This spec covers:

- ORDS privileges
- optional ORDS roles
- module privilege assignment
- schema-level and pool-level JWT trust configuration
- provider-specific ORDS security patterns

This spec does not cover:

- React auth state or login UX (see `authentication-spec-v1.md`)
- Oracle row-level security or VPD policy design (see `database-session-context-v1.md`)
- external IdP tenant provisioning
- secret management infrastructure outside the repository

---

## 4. Security Objects in ROAD

### 4.1 Privileges

A privilege is the primary ORDS access-control unit in ROAD. Every protected module or protected path must be guarded by a named ORDS privilege.

### 4.2 Roles

Roles are optional. They are used only when the selected provider profile or application requires role-based authorisation in addition to privilege or scope checks.

### 4.3 Module Protection

Privileges may be attached:

- to an entire module
- to selected path patterns

ROAD prefers whole-module protection where practical.

### 4.4 Trust Configuration

Depending on the provider profile, ORDS security also includes:

- JWT profile trust settings
- ORDS-native OAuth client registration

---

## 5. File and Deployment Structure

Security artifacts must fit the ROAD SQL runner structure:

```text
api/
  modules/
    <module_name>/
      module.create.sql
      module.drop.sql
      privileges.create.sql
      privileges.drop.sql
```

Rules:

- module definitions live with the module
- privilege definitions live in the same module directory unless intentionally centralised
- `deploy/create/90_rest.sql` references all module and privilege create scripts
- `deploy/drop/90_rest.sql` references all module and privilege drop scripts in reverse-safe order

---

## 6. Privilege Definition Standard

### 6.1 Naming

Privilege names must be stable and descriptive. A short namespaced form is recommended.

Examples:

```text
customers.read
customers.write
orders.approval
```

Where a profile relies on scope-based JWT authorisation, the privilege name must match the scope value expected in the token.

### 6.2 Scope-Based Default

The ROAD default is:

- an ORDS privilege protects the module or path
- the token carries the same privilege name in `scope` or `scp`
- ORDS allows access only if token validation succeeds and the required privilege is satisfied

### 6.3 Role-Based Variant

Where role-based JWT profiles are used:

- roles must be defined explicitly
- the mapped JWT claim must resolve to ORDS role names
- role requirements must be documented in the privilege script comments

### 6.4 Whole Module vs Selected Paths

Use `ORDS.SET_MODULE_PRIVILEGE` when protecting a full module.

Use path-based protection only when:

- a module intentionally contains both public and protected paths, or
- different paths require materially different privileges

---

## 7. Provider-Neutral Security Rules

### 7.1 Protected Endpoints

Every protected endpoint must be behind an ORDS privilege.

### 7.2 Public Endpoints

Public endpoints must be explicit and limited.

Typical public endpoints:

- login endpoints
- JWKS endpoints
- selected health or bootstrap endpoints where intentionally public

### 7.3 Handler Responsibility

ORDS handlers must assume ORDS has already applied the correct security gate. Handlers must not parse tokens or decide whether the request is authenticated.

### 7.4 Status Expectations

At the ORDS security boundary:

- invalid or missing authentication yields `401`
- valid authentication without sufficient ORDS privilege/scope also yields `401` in the v1 ORDS-first profile

---

## 8. JWT Profile Management

### 8.1 Schema-Level JWT Profile

For schema-managed JWT trust, ROAD uses a schema-level JWT profile. This is the standard pattern for self-contained or schema-owned JWT trust setup.

### 8.2 Administrative Path

Where an administrative user manages JWT trust on behalf of another schema, the administrative ORDS security API should be used.

### 8.3 Pool-Level JWT Profile

Some deployments use pool-level JWT settings instead of schema-level profiles.

### 8.4 Precedence Rule

If pool-level JWT trust is configured, ROAD must treat it as the active source of truth. Schema-level assumptions must not silently override or conflict with pool-level configuration.

### 8.5 One Active Schema-Level Profile

Only one schema-level JWT trust profile is assumed per schema in v1.

---

## 9. Required JWT Trust Settings

### 9.1 Issuer

The configured issuer must match the token `iss` claim exactly.

### 9.2 Audience

The configured audience must match the token `aud` claim exactly.

### 9.3 JWKS URL

The configured JWKS URL must resolve to a publicly reachable JWKS document for the token issuer.

### 9.4 Allowed Skew

Clock-skew tolerance may be configured where appropriate.

### 9.5 Allowed Age

Maximum token age may be configured where appropriate.

### 9.6 Role Claim Name

Where role-based JWT authorisation is used, the mapped role-claim path must be explicit and valid.

---

## 10. Provider Pattern: `external_oidc`

### 10.1 Model

An external OIDC provider issues the JWT. ORDS validates that JWT through issuer, audience, and JWKS configuration.

### 10.2 Privilege Alignment

For the default scope-based pattern, the token `scope` or `scp` claim must contain the ORDS privilege names protecting the requested resource.

### 10.3 Configuration Contract

This profile requires:

- exact issuer
- exact audience
- correct JWKS URL
- explicit privilege / scope alignment

### 10.4 Common Failure Modes

Typical problems include:

- issuer mismatch
- audience mismatch
- unreachable JWKS
- wrong signing key
- missing required scope

---

## 11. Provider Pattern: `ords_oauth`

### 11.1 Model

ORDS issues and validates the token through its native OAuth model.

### 11.2 OAuth Clients

OAuth clients must be registered as code or through an explicit administrative process. The privileges granted to those clients must be stable and reviewable.

### 11.3 Grant Types

Supported grant types depend on the application use case, but the framework source prototype demonstrates:

- `client_credentials`
- `authorization_code`

### 11.4 Legacy API Caution

The source prototype uses older `OAUTH` package examples. ROAD examples should prefer current ORDS-supported security APIs when formalising this profile.

---

## 12. Provider Pattern: `ords_local_jwt_scaffold`

### 12.1 Model

The application schema exposes:

- a public login endpoint
- a public JWKS endpoint
- a protected module behind an ORDS privilege
- a schema-level JWT profile trusting the local JWKS

### 12.2 Public Endpoints

The login endpoint and JWKS endpoint must remain public by design.

### 12.3 Protected Endpoints

Protected business endpoints must still use explicit ORDS privileges and must not rely on the login package alone as the security boundary.

### 12.4 Key Rotation Caveat

Because ORDS caches JWKS metadata, key rotation may require a short refresh window before all old tokens are rejected consistently.

### 12.5 Restriction

This pattern is development-only in ROAD and must be marked accordingly in all documentation and template assets.

---

## 13. Deployment and Teardown Rules

### 13.1 Create Scripts

Security create scripts must:

- be explicit
- be safe to rerun where practical
- fail clearly on unexpected errors

### 13.2 Drop Scripts

Security drop scripts must:

- remove privileges, mappings, and modules in a safe order
- tolerate non-existence where appropriate
- avoid masking unexpected failures

### 13.3 Environment Variables and Placeholders

Environment-specific details such as issuer, audience, JWKS URL, and ORDS URL base paths must be externalised through placeholders or deployment-time configuration.

---

## 14. Testing Requirements

At minimum, ORDS security configuration must be validated with tests covering:

| Test Case | Expected Status |
|---|---|
| Protected endpoint without token | 401 |
| Protected endpoint with valid token | 200 |
| Valid token with wrong scope or missing privilege | 401 in the v1 ORDS-first profile |
| Wrong issuer / audience / signature | 401 |
| Public login endpoint reachable where intended | 200 or profile-specific success |
| Public JWKS endpoint reachable where intended | 200 |

Where key rotation is supported, tests should also verify post-rotation behaviour.

---

## 15. What This Spec Does Not Cover

- frontend login and token storage behaviour (see `authentication-spec-v1.md`)
- Oracle session context and VPD integration (see `database-session-context-v1.md`)
- IdP tenant provisioning steps
- application-specific business authorisation rules inside PL/SQL

---

## 16. Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-04-21 | Initial draft based on external OIDC, ORDS OAuth, and ORDS local JWT scaffold source implementations |
