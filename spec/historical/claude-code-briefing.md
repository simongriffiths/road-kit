# Claude Code Briefing — Framework Spec Merge
**Prepared:** 2026-04-18  
**Prepared by:** Claude (claude.ai session)  
**Intended recipient:** Claude Code

---

## 1. What This Briefing Is

This document gives you full context to complete a spec merge task. It summarises:

- The framework spec suite already produced
- The three specs to be reverse engineered from working prototypes
- The open design question about dual auth models
- Conventions to follow so new specs integrate cleanly
- A briefing section for Codex (the subsequent build agent)

Read this document fully before touching any files.

---

## 2. The Framework

This is a spec suite for building API-first web applications on Oracle Autonomous Database. The stack is:

- **Oracle ADB** — database, PL/SQL packages, static file hosting
- **ORDS** (ADB built-in) — REST API and React static file delivery
- **React + TypeScript + Vite** — pure client-side, served from ORDS
- **SQLcl** — database deployment and test execution
- **Bash** — pipeline orchestration

Key architectural decisions:
- No local servers — React served from ADB ORDS in all environments
- Same origin — React app and API share the same host, no CORS
- Thin handlers — ORDS handler PL/SQL calls one package procedure only
- Agent-operated — designed for LLM agent execution, not a human team
- Three environments: dev, test, prod
- Manual gate before prod promotion

---

## 3. Existing Spec Suite

All specs are in the project. The master index is `framework-spec-index-v1.md`. Here is the full list:

| File | Status | Description |
|---|---|---|
| `framework-spec-index-v1.md` | ✅ Complete | Master index — relationships, reading order, conventions |
| `sql-runner-framework-spec-v2.md` | ✅ Complete | Directory structure, artifact rules, precedence model |
| `run-sql-sh-spec-v2.md` | ✅ Complete | Shell script contract for SQLcl execution |
| `ords-api-design-standards-v1.md` | ✅ Complete | URL conventions, response shapes, handler contract |
| `error-handling-contract-v1.md` | ✅ Complete | Error classification, logging, client-side handling |
| `react-project-structure-conventions-v1.md` | ✅ Complete | Directory layout, API client, auth, component rules |
| `local-dev-environment-v1.md` | ✅ Complete | Wallet setup, SQLcl CONNMGR, React build and deploy |
| `automated-testing-strategy-v1.md` | ✅ Complete | SQL, endpoint (curl), and component (Vitest) tests |
| `cicd-pipeline-v1.md` | ✅ Complete | Three-environment pipeline, promotion gates |

The existing specs contain placeholder references to three external specs marked as "covered by separate projects." Your task is to produce those specs and integrate them.

---

## 4. Your Task — Three Specs to Produce

### 4.1 ORDS Security Configuration

**What it covers:**
- How ORDS privilege definitions, roles, and OAuth clients are managed as code
- How security configuration is versioned and deployable via the SQL runner framework
- Relationship to the `privileges.create.sql` / `privileges.drop.sql` pattern already in the framework

**Source material:**
- The owner's working ORDS security prototype
- Existing `api/modules/<module>/privileges.create.sql` pattern in the framework

**Where it is referenced in existing specs:**
- `ords-api-design-standards-v1.md` Section 11 — "What This Spec Does Not Cover"
- `framework-spec-index-v1.md` Section 3.5 — External Specifications

**Output file:** `ords-security-configuration-v1.md`

---

### 4.2 Authentication

**What it covers:**
- Two auth models (see Section 5 below — read carefully before writing this spec)
- JWT structure and claims
- How tokens are issued, validated, and expired
- How the React client handles token lifecycle
- How ORDS validates tokens on protected endpoints

**Source material:**
- Working ORDS self-certification prototype
- Working Auth0 integration prototype

**Where it is referenced in existing specs:**
- `react-project-structure-conventions-v1.md` Section 7 — Authentication (references `AuthContext`, `useAuth`, JWT in sessionStorage)
- `error-handling-contract-v1.md` Section 6.5 — 401 handling (clear token, redirect to login)
- `local-dev-environment-v1.md` Section 7.3 — deploy-react.sh
- `framework-spec-index-v1.md` Section 3.5 — External Specifications

**Output file:** `authentication-spec-v1.md`

---

### 4.3 Database Session & Context

**What it covers:**
- How the authenticated user's identity flows from the JWT into the Oracle session
- Use of `SYS_CONTEXT` / application context packages
- VPD / row-level security integration
- How PL/SQL packages access the current user without it being passed as a parameter

**Source material:**
- Working database session and context prototype

**Where it is referenced in existing specs:**
- `error-handling-contract-v1.md` Section 5.1 — `error_log` table captures `session_user`
- `framework-spec-index-v1.md` Section 3.5 — External Specifications

**Output file:** `database-session-context-v1.md`

---

## 5. The Dual Auth Model — Open Design Question

This is the most important design decision you need to resolve before writing the authentication spec.

**The situation:**

The owner has two working auth prototypes:

1. **ORDS self-certification** — ORDS issues the JWT itself. Simpler, no external dependency. Used for demo apps.
2. **Auth0 (external IdP)** — Auth0 issues the JWT. Production-grade identity management. Used for the council app (prod).

**The open question:**

Are these two models:

**Option A — Two separate implementations**
Different apps choose one model. The React client and ORDS handler contract differs between them. Two distinct auth setups with no shared abstraction.

**Option B — One interface, two backends**
The React client and ORDS handler contract is identical regardless of which model is used. Only the JWT issuer and validation mechanism differs. The app does not need to know which auth model is active.

**Option C — Phased**
ORDS self-cert is the default for all apps including demos. Auth0 is a named variant applied to specific apps (council app) where production identity management is required.

**Recommendation:**

Option B or C is strongly preferred. Option A leads to divergent React codebases and divergent ORDS configurations that are hard to maintain.

The JWT claims contract (what fields are in the token, what they mean) should be identical regardless of issuer. The difference is only in how the token is obtained (login flow) and how ORDS validates it (self-cert vs JWKS endpoint).

**Your job:**

Review both prototypes and determine which option best describes what is actually implemented. Document it as a first-class spec decision. If the prototypes diverge more than expected, flag this explicitly rather than papering over it.

---

## 6. Reverse Engineering Approach

For each prototype:

1. Read all relevant files — SQL packages, ORDS module scripts, shell scripts, React components
2. Identify implicit decisions (naming conventions, error handling patterns, token structure, etc.)
3. Document them as explicit spec — the same format and style as the existing specs
4. Cross-reference with existing specs — check for conflicts or gaps
5. Note anything in the prototype that contradicts an existing spec decision — flag it, do not silently resolve it

Do not invent behaviour not present in the prototype. If something is ambiguous, note it as an open question rather than making an assumption.

---

## 7. Spec Writing Conventions

Follow these conventions so new specs integrate cleanly with the existing suite:

**Format:**
- Markdown
- Top matter: `# Title`, `**Version:** 1.0`, `**Status:** Approved`
- Numbered sections
- Tables for structured information
- Code blocks with language tags for all code samples

**Style:**
- Present tense, imperative voice ("The handler must...", "Scripts must...")
- Each spec ends with a "What This Spec Does Not Cover" section listing what is handled elsewhere
- Cross-reference other specs by filename, not by title alone

**File naming:**
- `<topic>-<version>.md`
- Lowercase, hyphens, no spaces
- Examples: `ords-security-configuration-v1.md`, `authentication-spec-v1.md`

**Versioning:**
- New specs start at v1
- Amendments to existing specs increment to v2, v3 etc.
- Version history table at the bottom of each spec

---

## 8. Index Updates Required

After producing the three specs, update `framework-spec-index-v1.md`:

1. Move the three specs from Section 3.5 (External Specifications) into the appropriate subsections in Section 3
2. Add the new files to Section 3 tables
3. Update the dependency diagram in Section 4 to show the new specs
4. Update the reading order in Section 5
5. Update the version history in Section 9

---

## 9. Codex Build Briefing

*This section is for Codex — the build agent that will implement the framework after the spec merge is complete.*

---

### 9.1 What You Are Building

You are implementing an Oracle ADB + ORDS + React application framework. The full specification suite is in the project. Read `framework-spec-index-v1.md` first, then follow the reading order in Section 5 of that document.

### 9.2 Your Operating Model

- You are an LLM agent, not a human developer
- You operate in a Mac/Linux environment
- You invoke `run-sql.sh` for all SQL execution — never SQLcl directly
- You treat any non-zero exit as a hard failure requiring investigation
- You never embed credentials or put the wallet inside the project directory
- You never run tests against prod

### 9.3 Before You Write Any Code

Read these specs in order:

1. `framework-spec-index-v1.md` — full picture
2. `sql-runner-framework-spec-v2.md` — directory structure and artifact rules
3. `run-sql-sh-spec-v2.md` — how to execute SQL
4. `local-dev-environment-v1.md` — how to connect and deploy
5. `ords-api-design-standards-v1.md` — API contract
6. `error-handling-contract-v1.md` — error behaviour
7. `authentication-spec-v1.md` — auth model (produced by Claude Code merge)
8. `ords-security-configuration-v1.md` — ORDS security (produced by Claude Code merge)
9. `database-session-context-v1.md` — session context (produced by Claude Code merge)
10. `react-project-structure-conventions-v1.md` — React conventions
11. `automated-testing-strategy-v1.md` — what tests to write
12. `cicd-pipeline-v1.md` — deployment flow

### 9.4 Non-Negotiable Rules

These rules are repeated here because violations are the most common source of build failures:

- **One artifact per file.** `db/tables/customer.create.sql` not a combined script.
- **Partner drop scripts required.** Every create script needs a drop script.
- **Handlers call one package procedure.** No SQL, no logic, no branching in handlers.
- **All errors via `error_api`.** No ad-hoc error handling in handlers or packages.
- **Tests before promotion.** Never promote to the next environment without running the full test suite.
- **Wallet path is `/opt/oracle/wallet/<app_name>/`.** Never inside the project.
- **`TNS_ADMIN` must be set** before any SQLcl invocation.
- **`set -o pipefail`** must be at the top of every bash script.

### 9.5 When Something Is Unclear

Check the spec first. If the spec does not cover it, check the "What This Spec Does Not Cover" section of the relevant spec — it will point you to the right document. If it is genuinely not covered, flag it as an open question rather than making an assumption.

### 9.6 Token Budget Guidance

The spec suite is large. To avoid re-reading everything on every task:

- Read the index once per session
- Read only the specs relevant to the current task
- The index's "Key Conventions At a Glance" table (Section 6) covers the most important rules in one place
- The "Key Scripts At a Glance" table (Section 7) covers the entry points

---

## 10. Summary of Actions Required

### Claude Code (you):

- [ ] Review ORDS security prototype → produce `ords-security-configuration-v1.md`
- [ ] Review both auth prototypes → resolve dual auth model question → produce `authentication-spec-v1.md`
- [ ] Review session context prototype → produce `database-session-context-v1.md`
- [ ] Update `framework-spec-index-v1.md` to integrate all three new specs
- [ ] Flag any conflicts between prototype behaviour and existing specs

### Codex (subsequent):

- [ ] Read full spec suite before writing any code
- [ ] Implement framework following specs exactly
- [ ] Flag spec gaps rather than making assumptions
