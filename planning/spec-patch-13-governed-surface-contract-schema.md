# Specification Patch 13 — The Governed Surface Contract Schema

**Applies to:** framework surface. New `spec/governed-surface-contract.schema.json`,
`scripts/validate-gsc-contract.mjs`, `scripts/lib/json-schema-subset.mjs`, and their test and
fixture under `test/contract/`.
**Status:** draft schema, 14 November 2026. Validated by its own tests. No road-kit surface has a
contract document written to it yet.
**Decisions it implements:** road-atlas ledger D-04 (one contract per surface, with a state
section and a publication section) and D-07 (the schema implements the GSC definition). It
implements the Governed Surface Contract definition, version 0.1.0 (draft), in the `gsc`
repository.

---

## 1. What this is

`spec/governed-state-contract.schema.json` (tag `v0.1.0`) describes one governed action. This
schema describes a whole surface:

```
{
  "schema_version": "0.3.0",
  "gsc_definition_version": "0.1.0",
  "surface":     { id, title, description },
  "envelope":    { contract_version, identity, versioning, metadata_format, bindings, public_entries },
  "state":       { actions: [ action ... ], batch? },
  "publication": { provisional: true, views: [ view ... ] }
}
```

A document has `state`, `publication`, or both, matching the definition's three conformance
classes (full, state-only, data contract).

The v0.1.0 schema and the v0.2.0 projector are unchanged, and their tags stay immutable.

## 2. Path and version

The definition leaves both open (Appendix E, question 4). This patch chooses:

- **Path:** `spec/governed-surface-contract.schema.json`, the name road-tracker's spec, the
  definition (A.1) and the terminology notes already use.
- **Version:** `schema_version` `0.3.0`, the road-kit release that first carries it. This follows
  v0.1.0, whose schema version matched its release tag. A later release that changes the schema
  changes the constant. A release that leaves it alone keeps it.
- **`$id`** points at the `v0.3.0` tag, as v0.1.0's points at its own.

## 3. What changed from the v0.1.0 action

The state section reuses the v0.1.0 action shape (definition 9.1.3), changed where Appendix A.2 of
the definition records a difference.

| v0.1.0 | 0.3.0 | Definition |
|---|---|---|
| `capability_id` | `id` | 6.2, Appendix C |
| `action_resource: { method: "POST", path, intent }` | `action_resource: { rest?: { method, path }, mcp?, database? }`. `intent` removed | 5.6, A.2 |
| Actor model `public`, `authenticated`, `delegated` | `public`, `authenticated` | 5.2.6 |
| Rules `{ id, description }` | `{ id, kind, description, consumer_visible? }`, kind one of integrity, access, concurrency | 6.2, 8.4.1, 9.3.4 |
| No link between "changes a record" and concurrency | `changes_existing_record: true` requires a rule of kind `concurrency` | 6.6 |
| `outcomes.success { status 2xx }` | `outcomes.accepted { description, result? }` | 5.4 |
| Rejections `{ code, status 4xx, description, retryable }` | `{ rule_id, retryable, discloses_ids? }`, each naming a declared rule | 5.4, 6.4.2 |
| Non-disclosure written in the success description | `outcomes.non_disclosing: true` | 6.4.4 |
| `audit { transactional: true, fields }` | `audit { record, fields }`, fields must include the eight in 6.7.2 | 6.7 |
| Events `{ name, when }`, at least one | `{ name, when, payload? }`, zero or more | 6.8 |
| No envelope, views or batch | Defined | 5, 7, 6.9 |
| Idempotency `{ strategy, header \| fields }` | adds `retention` and `replays` | 6.5 |

## 4. Envelope

Declared once. It fixes what the definition makes non-negotiable, as constants, so a contract
cannot declare otherwise:

- `identity.principal_key` is `["issuer", "subject"]`; `identity.system_processes` is
  `run_as_system_owner`; `established_from` is `jwt`, `database_session` or both, never a request
  value (5.2).
- `versioning.response_field` is `contract_version`, and `versioning.discovery.rest` names the
  `GET` resource that returns the contract (5.3.3, 5.5). `expected_major_header` is optional
  (5.3.5).
- `metadata_format` is `json-schema-2020-12` (9.1.1).
- `public_entries` lists every action and view that needs no identity. The validator checks it
  against each entry's actor model (5.2.7).

## 5. Publication section

Marked `provisional: true`, because definition section 7 is Provisional. A view declares
`meaning`, `result` (a JSON Schema whose field descriptions carry the meaning of each field),
`keys`, `time`, `scope`, and where they apply `provenance`, `dependent_versions` and `read_tokens`.
A view with `access_rules_apply: true` must name the response field that says results are limited
(7.4.1).

## 6. Batch

`state.batch` is optional and marked `provisional: true`. It names the actions a batch may contain,
its limits, its idempotency key and whether it has a dry run. The design is spec-patch-14.

## 7. Validation

`node scripts/validate-gsc-contract.mjs <contract.json>` validates a contract against the schema,
then checks what JSON Schema cannot: identifiers unique across both sections, one entry per REST
resource, every rejection naming a declared rule, batch operations and read-token actions naming
declared actions, public entries agreeing with actor models, and no consumer-visible rules on a
non-disclosing action.

It is dependency-free. `scripts/lib/json-schema-subset.mjs` implements only the JSON Schema
keywords road-kit's schemas use, and refuses to run a schema that uses any other keyword, so a
keyword is never silently skipped.

`node test/contract/validate-governed-surface-contract-schema.mjs` runs on 14 November 2026:

```
[PASS] Governed Surface Contract schema 0.3.0: valid fixture accepted, 18 invalid variants refused
```

Each invalid variant breaks one requirement (for example a v0.1.0 rejection `status`, a
`delegated` actor, a change to an existing record without a concurrency rule, a decision record
without the idempotency key) and must be refused with the expected message. The v0.1.0 schema test
and the v0.2.0 projection test still pass.

## 8. Not done

- **Projector.** `scripts/project-mcp-descriptor.mjs` projects v0.1.0 contracts only. Projecting a
  0.3.0 surface into one tool per action, carrying `consumer_visible` rules and the contract
  version (9.2.2, 9.3.4), is the next step for MCP. road-tracker does not need MCP in Release 1.
- **Contract endpoint.** No road-kit code serves a contract at its discovery path yet.
- **Coverage check.** No check yet that every ORDS handler appears in a contract and every
  contract entry has a handler (9.5). `bin/check-handler-coverage.sh` checks a different thing.
- **A road-kit contract.** road-kit's first contract document belongs with its first governed
  action, spec-patch-11's completion request.

## 9. For other repositories

- **road-tracker** drops its own draft schema and writes `contract/road-tracker.gsc.json` against
  this one, validated with `scripts/validate-gsc-contract.mjs`. Its alignment note's items A1, A5,
  A8, A10 and A11 each have a field here: `replays` and `natural_key` fields, `changes_existing_record`,
  `DELETE` in `action_resource.rest.method`, `versioning`, and `dependent_versions`.
- **gsc** answers Appendix E question 4 with section 2 above, if Simon agrees.
- **road-ks** is the first case for a view with `provenance` across sources.
