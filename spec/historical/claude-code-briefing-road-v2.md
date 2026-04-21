# Claude Code Briefing — ROAD Stack Spec Merge & GitHub Release
**Prepared:** 2026-04-18  
**Prepared by:** Claude (claude.ai session)  
**Intended recipient:** Claude Code

---

## 1. The Stack

**ROAD** — React, ORDS, ADB, Direct

A personal open-source framework for building API-first web applications on Oracle Autonomous Database. No middleware layer — React talks directly to ORDS, which talks directly to Oracle ADB.

Positioned against MERN/MEAN as a serious alternative for Oracle-native development.

| Letter | Technology | Role |
|---|---|---|
| R | React + TypeScript + Vite | Pure client-side frontend |
| O | ORDS (ADB built-in) | REST API + static file delivery |
| A | Oracle Autonomous Database | Database, PL/SQL packages, file storage |
| D | Direct | No Node/Express middleware — React to ORDS is the whole backend |

**Tagline:** *Full-stack web development on Oracle ADB. No middleware. No compromise.*

---

## 2. GitHub Structure

The public release lives across two repositories:

### `road-stack/road-reference`
The specification suite. All specs as markdown files. The authoritative source of framework conventions.

### `road-stack/road-kit`
A GitHub template repository. Clone or "Use this template" to start a new ROAD app. Contains the working tooling, directory skeleton, and demo app — with all owner-specific details removed.

Both repos live under a `road-stack` GitHub organisation (personal, not Oracle-affiliated).

---

## 3. `road-reference` Repository Structure

```
road-reference/
  README.md                               ← overview, what ROAD is, links to specs
  specs/
    00-index.md                           ← master index (framework-spec-index-v1.md)
    01-sql-runner-framework.md            ← sql-runner-framework-spec-v2.md
    02-run-sql-sh.md                      ← run-sql-sh-spec-v2.md
    03-ords-api-design-standards.md       ← ords-api-design-standards-v1.md
    04-error-handling-contract.md         ← error-handling-contract-v1.md
    05-authentication.md                  ← authentication-spec-v1.md (TO BE PRODUCED)
    06-ords-security-configuration.md     ← ords-security-configuration-v1.md (TO BE PRODUCED)
    07-database-session-context.md        ← database-session-context-v1.md (TO BE PRODUCED)
    08-react-project-structure.md         ← react-project-structure-conventions-v1.md
    09-local-dev-environment.md           ← local-dev-environment-v1.md
    10-automated-testing-strategy.md      ← automated-testing-strategy-v1.md
    11-cicd-pipeline.md                   ← cicd-pipeline-v1.md
  CHANGELOG.md
  LICENSE                                 ← MIT
```

Specs are numbered for reading order. Filenames are slugified spec titles.

---

## 4. `road-kit` Repository Structure

```
road-kit/
  README.md                               ← getting started guide
  .github/
    ISSUE_TEMPLATE/
    pull_request_template.md
  bin/
    run-sql.sh                            ← production-ready implementation
    pipeline.sh                           ← full deploy + test + promote
    deploy-react.sh                       ← React build + upload to ORDS
    run-endpoint-tests.sh                 ← HTTP endpoint test runner
    get-test-token.sh                     ← JWT for endpoint tests
    assert-http.sh                        ← assertion helper
    verify-connection.sql                 ← connection smoke test
  db/
    tables/                               ← empty, ready for artifacts
    indexes/
    synonyms/
    views/
    types/
    package_specs/
    package_bodies/
    type_bodies/
    standalone/
      assert_true.prc                     ← test utility
  api/
    modules/                              ← empty, ready for ORDS modules
  deploy/
    create/
      00_full.sql                         ← master orchestration (empty skeleton)
      05_types.sql
      10_tables.sql
      20_indexes.sql
      30_synonyms.sql
      40_views.sql
      60_package_specs.sql
      70_package_bodies.sql
      75_type_bodies.sql
      80_standalone.sql
      90_rest.sql
      95_data.sql
      99_verify.sql
    drop/
      00_full.sql
      90_rest.sql
      80_standalone.sql
      75_type_bodies.sql
      70_package_bodies.sql
      60_package_specs.sql
      40_views.sql
      30_synonyms.sql
      20_indexes.sql
      10_tables.sql
      05_types.sql
    test/
      00_test_setup.sql
  test/
    smoke/
    contract/
    endpoint/
      00_endpoint.sh
  app/                                    ← React app skeleton
    src/
      api/
        client.ts
      components/
        common/
          Toast.tsx
          Toast.test.tsx
          ErrorBanner.tsx
          ErrorBanner.test.tsx
      context/
        AuthContext.tsx
        ErrorContext.tsx
      hooks/
        useAuth.ts
      pages/
        LoginPage.tsx
        HomePage.tsx
      types/
        api.ts
      utils/
        auth.ts
      App.tsx
      main.tsx
      router.tsx
    public/
    .env.example
    .env.development.example
    .env.production.example
    vite.config.ts
    tsconfig.json
    package.json
  logs/
    .gitkeep
  .gitignore
  LICENSE                                 ← MIT
```

---

## 5. What Gets Stripped for Public Release

The following must be removed or replaced before the public release:

| Remove | Replace with |
|---|---|
| Owner's app names and schema names | `<app_name>` placeholder |
| Council app references | Generic "example app" references |
| AIDA references | Removed entirely |
| Oracle-internal references | Removed entirely |
| Specific ADB hostnames/URLs | `<adb-host>` placeholder |
| Any wallet paths beyond the standard `/opt/oracle/wallet/<app_name>/` | Standard placeholder only |
| Owner's TNS alias names | `<tns_alias>` placeholder |

The framework is inherently Oracle/ORDS/ADB-specific — that stays. Only personal/project-specific details are stripped.

---

## 6. README Structure for `road-kit`

The README is the primary onboarding document for v1. It must cover:

```
1. What is ROAD?
   - The acronym and what each letter means
   - The "no middleware" proposition
   - Comparison with MERN/MEAN (one paragraph)

2. Prerequisites
   - Oracle ADB instance
   - ADB wallet downloaded
   - SQLcl installed
   - Node.js + npm
   - Bash (Mac/Linux)

3. Quick Start
   - Use this template → clone
   - Set up wallet
   - Configure CONNMGR connections
   - Run bin/verify-connection.sql
   - Run deploy/create/00_full.sql
   - Build and deploy React app
   - Open in browser

4. Repository Structure
   - Brief description of each top-level directory

5. Specification Suite
   - Link to road-reference repo
   - One-line description of each spec

6. Demo Apps
   - List of demo apps (separate repos, links when available)

7. License
   - MIT
```

---

## 7. Your Tasks (Claude Code)

### Task 1 — Spec Merge (primary task)

Produce the three missing specs by reverse engineering the owner's prototypes:

- [ ] `ords-security-configuration-v1.md`
- [ ] `authentication-spec-v1.md` — resolve dual auth model (ORDS self-cert vs Auth0) first
- [ ] `database-session-context-v1.md`

Follow the approach and conventions in Section 6 and 7 of the original briefing (reproduced below).

Update `framework-spec-index-v1.md` to integrate all three specs:
- Move from Section 3.5 (External) into appropriate subsections in Section 3
- Update the dependency diagram
- Update the reading order
- Update version history

### Task 2 — Public Release Preparation

After the spec merge is complete:

- [ ] Rename all spec files to the numbered slug format (`00-index.md`, `01-sql-runner-framework.md` etc.)
- [ ] Strip all owner-specific details (see Section 5 above)
- [ ] Produce the `road-reference` repository structure with all specs
- [ ] Produce the `road-kit` repository skeleton with working tooling stubs
- [ ] Produce the `road-kit` README following the structure in Section 6
- [ ] Produce a `CHANGELOG.md` for v1.0.0

### Task 3 — Codex Handoff

After Tasks 1 and 2 are complete, update the Codex briefing section (Section 9 of the original briefing) to reference ROAD by name and point to the public repo structure.

---

## 8. Spec Writing Conventions

*(Reproduced from original briefing for completeness)*

**Format:**
- Markdown
- Top matter: `# Title`, `**Version:** 1.0`, `**Status:** Approved`
- Numbered sections
- Tables for structured information
- Code blocks with language tags for all code samples

**Style:**
- Present tense, imperative voice ("The handler must...", "Scripts must...")
- Each spec ends with a "What This Spec Does Not Cover" section
- Cross-reference other specs by filename

**File naming (internal working files):**
- `<topic>-<version>.md` during development
- Renamed to numbered slug format for public release

---

## 9. Dual Auth Model — Open Design Question

*(Reproduced and updated from original briefing)*

The owner has two working auth prototypes:

1. **ORDS self-certification** — ORDS issues the JWT. Simpler, no external dependency. Demo apps.
2. **Auth0 (external IdP)** — Auth0 issues the JWT. Production-grade. Council app (prod).

Recommended resolution: **One interface, two backends.** The React client and ORDS handler contract is identical. Only JWT issuance and validation differs. The app does not need to know which auth model is active.

JWT claims contract must be identical regardless of issuer. Difference is only in:
- How the token is obtained (login flow)
- How ORDS validates it (self-cert vs JWKS endpoint)

Review both prototypes and determine if this is achievable. If the prototypes diverge significantly, flag it explicitly.

---

## 10. Codex Build Briefing

*For Codex — the build agent that implements apps using the ROAD stack.*

---

### What You Are Building On

You are building on the **ROAD stack** — React, ORDS, ADB, Direct. Full specification suite is in `road-reference`. Start with `specs/00-index.md`.

### The No-Middleware Rule

There is no Node.js, no Express, no backend server. React calls ORDS REST endpoints directly. ORDS calls PL/SQL packages. That is the entire stack. If you find yourself reaching for a Node backend, stop — you are off the ROAD.

### Your Operating Model

- LLM agent operating on Mac/Linux
- All SQL execution via `bin/run-sql.sh` — never SQLcl directly
- All React deployment via `bin/deploy-react.sh` — no local dev server
- Non-zero exit = hard failure, investigate before retrying
- Never embed credentials, never put wallet inside project

### Reading Order

Read `specs/00-index.md` first. Follow the reading order in Section 5 of that document. For token efficiency, the index's "Key Conventions At a Glance" table covers the most important rules in one place.

### Non-Negotiable Rules

- One artifact per file
- Partner drop scripts required
- Handlers call one package procedure only — no logic, no SQL
- All errors via `error_api` package
- Tests before every promotion
- Wallet at `/opt/oracle/wallet/<app_name>/` — never inside project
- `TNS_ADMIN` set before any SQLcl invocation
- `set -o pipefail` at top of every bash script
- Test utilities never deployed to prod
- Manual approval required before prod promotion

### When Something Is Unclear

Check `specs/00-index.md` first. Each spec's "What This Spec Does Not Cover" section points to the right document. Flag genuine gaps rather than assuming.
