# Governed State Contracts Proof Plan

**Version:** 1.0  
**Status:** In progress. W1 and W2 released; the Governed Surface Contract schema and decision record released in v0.3.0; W3 met by the todo demo (ruled 19 November 2026); W4 not started  
**Scope:** road-kit engineering only

## Progress

| Stage | State | Evidence |
| --- | --- | --- |
| W1 — Canonical contract schema | Released 4 September 2026 | Tag `v0.1.0` (commit `44afcc6`); `planning/action-w1-contract-schema.md`; road-atlas `RK-10` |
| W2 — Deterministic descriptor projection | Released 4 September 2026 | Tag `v0.2.0` (commit `69e0b32`); `planning/action-w2-mcp-descriptor-projection.md`; road-atlas `RK-11` |
| Decision record and 200 outcomes | Released 14 November 2026 | Tag `v0.3.0`; `planning/spec-patch-12-business-decisions-and-decision-record.md`; road-atlas `D-05`, `RK-13` |
| Governed Surface Contract schema | Released as a draft 14 November 2026 | Tag `v0.3.0`; `planning/spec-patch-13-governed-surface-contract-schema.md`; road-atlas `D-04`, `D-07`, `RK-14` |
| W3 — Reference governed action | **Met by the simple todo demo, ruled 19 November 2026.** Spec-patches 11 and 10 are withdrawn. The event hand-off is not part of road-kit's W3; one of the more complex apps can demonstrate it | `planning/spec-patch-12-business-decisions-and-decision-record.md` (v0.3.0), `planning/spec-patch-15-agent-api-keys-and-cli.md`, `planning/spec-patch-16-gsc-reference-implementation.md`, `planning/spec-patch-17-todo-page.md` (v0.4.0); road-atlas `RK-12` |
| W4 — End-to-end proof | Not started | — |

The name has changed. On 29 September 2026 the contract became the Governed Surface Contract, with a governed state contract (proposals inward) and a governed publication contract (data outward). The W1 schema describes one governed action, which is part of the governed state contract. `spec/governed-surface-contract.schema.json` (schema `0.3.0`, tag `v0.3.0`) describes a whole surface and implements the GSC definition 0.1.0, which lives in the `gsc` repository. The `v0.1.0` and `v0.2.0` tags are unchanged.

## Purpose

This plan develops Governed State Contracts as reproducible road-kit evidence. It is independent of `simongriffiths.io` editorial and publication work. The website may cite a completed release, but no website date or article schedule authorises, accelerates, or blocks framework work.

The plan builds evidence in stages: a canonical contract schema, deterministic consumer output, a reference governed action, and an end-to-end demonstration. Every stage produces verification evidence and, when ready for public reference, an immutable tag.

## Boundaries

This plan owns road-kit source, tests, implementation decisions, and releases. It does not own blog copy, Hugo pages, editorial approval, or public publishing cadence.

The current website-side action file, `working/June-restructure/action-road-kit-w1-contract-schema.md` in simongriffiths.io, was the proposed W1 implementation brief. Its approved content was restated in `planning/action-w1-contract-schema.md`, which is the execution record for W1.

## Working principles

- Build only what can be verified in this repository.
- Keep the contract schema canonical and machine-readable; downstream representations are consumers, not competing specifications.
- Use immutable annotated tags for releases cited outside this repository.
- Follow ROAD's established test, ORDS, PL/SQL, security, and deployment conventions.
- For Oracle database work, inspect the relevant execution history before execution and use the approved SQL runner workflow.
- Do not make a framework release contingent on a matching website change.

## W1 — Canonical contract schema

Create the versioned Governed State Contract schema, a valid newsletter-subscription-request fixture, and a dependency-free structural test. The fixture is informed by ROAD Blogger's subscription lifecycle but does not modify ROAD Blogger. It is a target contract, not a claim that existing ROAD Blogger request handling already conforms exactly.

W1 is complete when the schema and fixture parse; the structural test passes without a new dependency; only intended files change; and the approved `v0.1.0` annotated tag is created and pushed. The tag is optional website evidence, not a website delivery prerequisite.

## W2 — Deterministic descriptor projection

Build a deterministic consumer that projects a W1 contract into an MCP tool descriptor. Test stable output from the W1 fixture and make clear which attributes are preserved, transformed, or deliberately excluded. Release only when generation and validation are repeatable.

## W3 — Reference governed action

Implement one complete governed action in road-kit: a proposal resource, authoritative PL/SQL decision path, current-state re-read, structured outcomes, same-transaction audit, and after-commit event hand-off. Select the target domain in a separate approved action file. Before any SQL work, inspect database engineering history and execute only through the repository's approved runner.

**Ruled 19 November 2026.** The simple todo demo satisfies W3: a governed surface with proposals, an authoritative PL/SQL decision path, a re-read of current state through the read token, structured outcomes, and audit through the decision record. The after-commit event hand-off in the sentence above is not provided by road-kit. Spec-patches 10 and 11, which designed it, are withdrawn, and another app can demonstrate events. What `v0.4.0` supports as a W3 claim is limited to what its tests and documentation show (see "Release and evidence interface").

## W4 — End-to-end proof

Demonstrate the stated loop from contract through generated descriptor and proposal to authoritative decision, audit, and event. Verification must be automated or repeatable, documented in the repository, and suitable for external readers to reproduce within its stated environment assumptions.

## Release and evidence interface

For every public proof release:

1. Run the release's documented verification suite.
2. Record the exact commit and create an immutable annotated tag.
3. Publish no claim beyond the tests and documentation that support it.
4. Record which external claim the release can support: schema reference (W1), generated descriptor (W2), reference implementation (W3), or end-to-end proof (W4).

The website may later link to that tag. It remains responsible for checking that its wording matches the release; road-kit has no obligation to coordinate timing.

## Next action

W3 is met by the simple todo demo (ruled 19 November 2026); spec-patches 10 and 11 are withdrawn and build plans 10 and 11 are not going ahead. W4 describes a loop that ends in an event, so its wording needs a ruling: it can be demonstrated in one of the more complex apps, or reworded to end at the audit. The batch and database-user identity path (spec-patch-14) wait for Simon's ruling on its open points. No ROAD Blogger change is authorised by this plan.
