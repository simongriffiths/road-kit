---
name: ords-authentication
description: Use when working on ORDS authentication, OAuth2 clients, privileges, roles, or external JWT trust. Prefer current ORDS_SECURITY and ORDS_SECURITY_ADMIN APIs, and consult the bundled reference before using deprecated OAUTH or OAUTH_ADMIN package examples.
---

# ORDS Authentication

Use this skill when implementing or reviewing ORDS authentication and authorization flows.

## Workflow

1. Read [references/ords-authentication.md](references/ords-authentication.md) before changing ORDS auth code or documentation.
2. Prefer `ORDS_SECURITY` and `ORDS_SECURITY_ADMIN` for new work.
3. Do not use `OAUTH` or `OAUTH_ADMIN` for new examples unless you are documenting legacy behavior explicitly.
4. For external IdP JWT trust:
   - use schema-level JWT profiles with `ORDS_SECURITY.CREATE_JWT_PROFILE` or `ORDS_SECURITY_ADMIN.CREATE_JWT_PROFILE`, or
   - use pool-level `security.jwt.profile.*` settings when the deployment is configured in pool mode.
5. For schema-level scope-based JWT profiles, ensure the token `scope` or `scp` claim contains the ORDS privilege names protecting the resource.
6. For role-based JWT profiles, use a valid JSON pointer in `p_role_claim_name` such as `/roles`, and ensure the claim resolves to ORDS role names.
7. When protecting a full module, prefer `ORDS.SET_MODULE_PRIVILEGE`; use `p_patterns` when protecting specific paths only.

## Checks

- Verify whether the environment is using schema-level or pool-level JWT profiles.
- Verify issuer, audience, and JWKS values match the external token exactly.
- Verify privilege names align with JWT scopes when using scope-based JWT profiles.
- Verify role names align with the role claim when using role-based JWT profiles.
- Verify examples use current package names and current APIs.
