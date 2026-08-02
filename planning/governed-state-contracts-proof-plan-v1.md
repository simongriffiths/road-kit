# Governed State Contracts Proof Plan

**Version:** 1.0  
**Status:** Proposed  
**Scope:** road-kit engineering only

## Purpose

This plan develops Governed State Contracts as reproducible road-kit evidence. It is independent of `simongriffiths.io` editorial and publication work. The website may cite a completed release, but no website date or article schedule authorises, accelerates, or blocks framework work.

The plan builds evidence in stages: a canonical contract schema, deterministic consumer output, a reference governed action, and an end-to-end demonstration. Every stage produces verification evidence and, when ready for public reference, an immutable tag.

## Boundaries

This plan owns road-kit source, tests, implementation decisions, and releases. It does not own blog copy, Hugo pages, editorial approval, or public publishing cadence.

The current website-side action file, `working/June-restructure/action-road-kit-w1-contract-schema.md` in simongriffiths.io, is the proposed W1 implementation brief. Before W1 begins, copy or restate its approved content in a road-kit-local action file so this repository retains the execution record. Do not execute it until Simon gives technical sign-off.

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

W1 is the next proposed technical action. It remains paused pending Simon's technical sign-off and a road-kit-local execution brief. No database, ORDS, deployment, or ROAD Blogger change is authorised by this plan.
