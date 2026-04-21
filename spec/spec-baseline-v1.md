# ROAD Specification Baseline
**Version:** 1.0  
**Status:** Frozen

---

## 1. Purpose

This document freezes the current ROAD specification baseline for implementation planning and build work.

It records:

- the exact specification set included in the baseline
- the maturity state of each included spec at freeze time
- which draft areas are intentionally carried forward into the build baseline

After this freeze point, changes to the baseline must be explicit and reviewed. No spec should drift implicitly during implementation.

---

## 2. Baseline Freeze Point

| Item | Value |
|---|---|
| Freeze date | 2026-04-21 |
| Repository | `road2` |
| Baseline label | `spec-baseline-v1` |
| Intent | Stable framework baseline for implementation planning |

---

## 3. Included Specification Set

### 3.1 Database & Deployment

| Spec | File | Version | Status at Freeze |
|---|---|---|---|
| SQL Runner Framework | `sql-runner-framework-spec-v2.md` | 2.0 — Amended | Resolved |
| run-sql.sh | `run-sql-sh-spec-v2.md` | 2.0 — Amended | Resolved |

### 3.2 API Layer

| Spec | File | Version | Status at Freeze |
|---|---|---|---|
| ORDS API Design Standards | `ords-api-design-standards-v1.md` | 1.0 | Approved |
| Error Handling Contract | `error-handling-contract-v1.md` | 1.0 | Approved |
| Authentication | `authentication-spec-v1.md` | 1.0 | Draft |
| ORDS Security Configuration | `ords-security-configuration-v1.md` | 1.0 | Draft |
| Database Session Context | `database-session-context-v1.md` | 1.0 | Draft |
| File Upload and UI Delivery | `file-upload-and-ui-delivery-spec-v1.md` | 1.0 | Draft |

### 3.3 Frontend

| Spec | File | Version | Status at Freeze |
|---|---|---|---|
| React Project Structure & Conventions | `react-project-structure-conventions-v1.md` | 1.0 | Approved |

### 3.4 Environment & Operations

| Spec | File | Version | Status at Freeze |
|---|---|---|---|
| Local Development Environment | `local-dev-environment-v1.md` | 1.0 | Approved |
| Automated Testing Strategy | `automated-testing-strategy-v1.md` | 1.0 | Approved |
| CI/CD Pipeline | `cicd-pipeline-v1.md` | 1.0 | Approved |

---

## 4. Draft Specs Included By Exception

The following specs remain `Draft`, but are intentionally included in the frozen build baseline:

- `authentication-spec-v1.md`
- `ords-security-configuration-v1.md`
- `database-session-context-v1.md`
- `file-upload-and-ui-delivery-spec-v1.md`

These are accepted into the baseline as controlled draft dependencies. Their current contents are part of the baseline, but their `Draft` status means they may still require refinement before production hardening or final approval.

---

## 5. Controlled Unresolved Areas

At freeze time, the framework still carries controlled unresolved areas in these domains:

- authentication provider and production-hardening details
- ORDS security configuration hardening and provider-specific operational nuance
- final database session-context implementation details
- file-upload and UI-delivery hardening details

These areas are not excluded from implementation planning. They are included as draft-controlled parts of the baseline and must not be changed casually during build work.

---

## 6. Change Control After Freeze

After this baseline is frozen:

- no spec is changed implicitly as part of implementation work
- any spec correction or design change must be explicit
- the framework index and this baseline document must be updated together if the frozen set changes
- draft specs may still be promoted, amended, or replaced, but only through deliberate revision

---

## 7. Historical Material

Historical briefing documents are not part of the frozen baseline. They live under:

```text
spec/historical/
```

They are reference material only and are not normative.
