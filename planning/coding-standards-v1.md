# ROAD Coding Standards
**Version:** 1.0  
**Status:** Proposed  
**Type:** Non-normative implementation guide

---

## 1. Purpose

This document provides one working coding-standards reference for implementation across the ROAD stack.

It is intended to guide build work in:

- SQL
- PL/SQL
- ORDS module scripts
- React and TypeScript
- Bash
- tests

The normative architecture remains in `spec/`. This document defines implementation discipline, style, and default coding patterns.

---

## 2. Source Hierarchy

When standards overlap, apply them in this order:

1. Frozen baseline in `spec/spec-baseline-v1.md`
2. Relevant normative spec in `spec/`
3. This coding standards guide
4. Oracle-specific guidance from the local `oracle-db-skills` set

If a proposed implementation conflicts with the normative specs, the spec wins.

---

## 3. Cross-Cutting Rules

- Prefer clarity over cleverness.
- Keep public contracts stable and implementation details private.
- Use small, composable units rather than large multipurpose files or procedures.
- Avoid hidden behavior and implicit side effects.
- Keep naming consistent across SQL, ORDS, React, and scripts.
- Do not leak internal database details to public clients.
- Make failures explicit and machine-diagnosable.
- Write code so it can be tested in isolation.

---

## 4. Naming Standards

### 4.1 General

- Use `snake_case` for database objects, JSON fields, ORDS resources, script names, and environment variables where already defined by the specs.
- Use `PascalCase` for React component filenames and component identifiers.
- Use `camelCase` for TypeScript functions, hooks, variables, and route params.

### 4.2 Database

- Tables: plural `snake_case`
- Views: plural `snake_case`
- Packages: `<domain>_api`, `<domain>_svc`, or similarly explicit suffixes
- Procedures/functions: verb-based and specific
- Columns: `snake_case`
- Constraints and indexes: deterministic, descriptive names

### 4.3 Files

- SQL files: ordered where execution order matters, descriptive where order does not
- Bash files: verb-based, kebab-case or existing repo convention
- React API modules: `camelCase.ts`
- React hooks: `useXxx.ts`
- React components: `PascalCase.tsx`

---

## 5. SQL Standards

### 5.1 Structure

- One clear purpose per script.
- Do not combine unrelated schema changes in the same file.
- Scripts must be safe to execute through `bin/run-sql.sh`.
- Use explicit statement terminators and SQLcl-compatible syntax only.

### 5.2 Style

- Use uppercase for SQL keywords.
- Use aligned, readable column lists for `SELECT`, `INSERT`, and `UPDATE`.
- Prefer one column per line in wide statements.
- Avoid overly compressed SQL.

### 5.3 Safety

- Do not embed credentials or secrets.
- Avoid dynamic SQL unless it is genuinely required.
- If dynamic SQL is required, parameterize and validate inputs strictly.
- Keep DDL and test/setup data separate.

### 5.4 Transactions

- Transaction ownership must be deliberate.
- Do not scatter commits through generic data-access code without reason.
- Deployment scripts may control transaction boundaries explicitly.

---

## 6. PL/SQL Standards

### 6.1 Package Design

- Use packages as the main unit of PL/SQL design.
- Keep package specs small and stable.
- Put implementation helpers in the package body unless another caller truly needs them.
- Prefer explicit public interfaces over global package state.

### 6.2 Procedure Design

- Each public procedure or function should do one clear job.
- Use meaningful parameter names with `p_` prefixes when that improves clarity.
- Use local variables sparingly and name them consistently.
- Prefer functions for single returned values and procedures for commands or multiple outputs.

### 6.3 Error Handling

- Handle expected business exceptions explicitly.
- Raise meaningful application errors for business-rule violations.
- Do not expose raw internal exceptions directly to API callers.
- Log where required by the error-handling contract, but keep API responses generic for server failures.

### 6.4 Package State

- Avoid request-specific package global state.
- Assume pooled sessions and reused connections.
- Prefer application context and explicit parameter passing over session-persistent package globals.

### 6.5 Comments

- Comment intent, assumptions, and non-obvious constraints.
- Do not narrate obvious syntax.
- Add a short header comment only where the package purpose is not already obvious from its name.

---

## 7. ORDS Standards

### 7.1 Handler Design

- Keep handlers thin.
- Handlers may extract parameters, call one package entry point, and emit the response.
- Business logic must not live in the handler body.
- String-building JSON by hand in handlers is discouraged unless unavoidable.

### 7.2 URL And Resource Design

- Follow the approved `/ords/<api_base_path>/api/v1/<resource>/` contract.
- Use plural lowercase `snake_case` resource names.
- Keep nesting shallow.
- Use HTTP method semantics correctly.

### 7.3 Response Design

- Collection responses use native ORDS collection shapes.
- Single-item responses return the object directly.
- Errors return the approved `{error, message}` structure and correct HTTP status.
- Do not invent per-endpoint response envelopes without strong reason.

### 7.4 Security

- Protected routes must be separated from public UI routes.
- Enforce `401` for ORDS-boundary authentication and privilege rejection in the v1 ORDS-first profile; reserve `403` for downstream application-level authorization where ROAD chooses to distinguish it.
- Keep provider-specific security details out of generic handler code.

---

## 8. React And TypeScript Standards

### 8.1 General

- Use TypeScript throughout.
- Keep components thin and focused on rendering and interaction.
- Put API logic in `src/api/`.
- Put data-loading behavior in hooks.
- Put auth and global error behavior in context providers.

### 8.2 Environment Variables

- Only use approved `VITE_` variables.
- `VITE_ORDS_BASE_URL` is consumed through the API client.
- `VITE_APP_NAME` and `VITE_UI_BASE_PATH` may be used only in bootstrap, routing, or build configuration.
- Components and feature hooks must not read `import.meta.env` directly.

### 8.3 TypeScript Style

- Use `strict` typing.
- Avoid `any`.
- Use `unknown` plus narrowing when needed.
- Define API response types explicitly.
- Keep function signatures and return types readable.

### 8.4 Component Rules

- One component per file.
- No raw `fetch` in components.
- No direct storage access in components.
- No business logic in page components beyond composition and top-level state orchestration.

### 8.5 Routing

- Route definitions belong in `src/router.tsx`.
- Protected routes must be grouped under a protection boundary.
- The app must work under `/ords/<ui_base_path>/ui/<app_name>/`, not only under `/`.

### 8.6 State

- Prefer local state first.
- Use context for truly shared state such as auth and global errors.
- Do not introduce extra state-management libraries unless the framework explicitly adopts one.

---

## 9. Bash Standards

### 9.1 Shell Discipline

- Use `bash`.
- Start scripts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- Quote variables unless omission is deliberate and safe.
- Prefer functions for non-trivial scripts.
- Fail fast on invalid input.

### 9.2 Argument Handling

- Accept explicit named arguments where the script contract defines them.
- Validate required arguments before doing work.
- Print usage to stderr on invalid invocation.
- Use exit code `2` for usage or input errors where the script contract requires it.

### 9.3 Logging

- Emit concise lifecycle markers.
- Write clear error messages to stderr.
- Keep console output readable and deterministic.
- Separate normal and debug behavior where the script spec requires it.

### 9.4 External Commands

- Check prerequisites before invocation.
- Prefer standard portable shell constructs.
- Avoid clever pipelines that obscure failure handling.

---

## 10. Testing Standards

### 10.1 General

- Every new slice should add the smallest useful tests needed to verify it.
- Prefer fast tests closest to the logic boundary.
- Do not rely on manual verification alone.

### 10.2 SQL And Endpoint Tests

- Run via the approved script entry points.
- Keep tests deterministic.
- Clean up created test data where necessary.
- Assert HTTP status codes explicitly.

### 10.3 React Tests

- Use Vitest and React Testing Library.
- Mock API modules rather than calling live ORDS for component tests.
- Test rendering, loading, empty, success, and relevant error paths.

---

## 11. Default Review Checklist

Before considering a change complete, check:

- Does it follow the relevant normative spec?
- Does it preserve public contract stability?
- Does it avoid leaking database or server internals?
- Is the naming consistent with ROAD conventions?
- Is the code thin at the framework edge and substantial in the right layer?
- Is there a clear test path for the change?
- Does it avoid introducing a second unofficial pattern for the same problem?

---

## 12. When To Escalate Back To Spec

Do not silently invent a new pattern when the change affects:

- public URLs
- response shapes
- auth semantics
- project identity/config flow
- environment model
- deployment model
- script contract
- file/directory conventions used across repos

Those require a spec or baseline update, not just a coding decision.
