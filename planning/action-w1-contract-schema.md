# Action File W1 — Governed State Contract Schema v0.1.0

**Status:** Ready for Simon's technical sign-off. Do not execute until this file's
release convention is approved. Restated here, in road-kit itself, from the approved
brief at `simongriffiths.io/working/June-restructure/action-road-kit-w1-contract-schema.md`,
per the boundary rule in `governed-state-contracts-proof-plan-v1.md` — this repository
keeps its own execution record rather than depending on the website repo's `working/`
drafts.

**Concern (single):** Add the first canonical, machine-readable Governed State
Contract schema to this repository, with an executable, dependency-free structural
test and one representative contract fixture. The fixture uses ROAD Blogger's real
newsletter subscription lifecycle. This action creates the input to later MCP
descriptor generation (W2); it does not create an MCP tool, ORDS endpoint, PL/SQL
package, database object, or public microsite schema page.

## Decisions carried by this action

- Canonical schema path: `spec/governed-state-contract.schema.json`.
- Initial schema version: `0.1.0`.
- Schema dialect: JSON Schema Draft 2020-12.
- The initial test command is dependency-free: `node test/contract/validate-governed-state-contract-schema.mjs`.
- Release convention: commit the approved schema and tests, run the test command,
  then create and push the immutable annotated tag `v0.1.0`. The microsite may cite
  that tag only after it exists; the tag is evidence for an exact schema claim, not a
  website delivery prerequisite.
- The initial fixture is `newsletter.subscription-request`, using ROAD Blogger's
  public `POST /subscribe` lifecycle. It represents a request to become subscribed,
  not a direct instruction that the reader is already active.

## Discovery — reconfirmed 4 September 2026 against this repository

1. Repository is `/Users/simon/Projects/road-kit` (the brief's recorded path,
   `/Users/Simon/Oracle/road2`, is stale — corrected here), remote
   `git@github.com:simongriffiths/road-kit.git`, branch `main`.
2. `spec/governed-state-contract.schema.json`, `test/contract/validate-governed-state-contract-schema.mjs`,
   and `test/contract/fixtures/governed-state-contract.valid.json` — confirmed absent.
3. Node.js `v25.9.0` available at `/opt/homebrew/bin/node`. No root-level
   `package.json` or `package-lock.json` exists — no established validator to
   conflict with. No dependency is installed for W1.
4. `bin/run-sql.sh` exists. No SQL is executed in W1.
5. `.codex/db-history.sqlite` exists (the brief's fallback caveat — record that W1
   performs no SQL and so does not need it — does not apply; the history surface is
   already live for W3 to use later).
6. Reviewed against road-blogger's subscriber baseline:
   `db/package_specs/sub_api.pks` confirms `p_honeypot` on the subscribe entry point
   and an `is_suppressed` check, matching the fixture's honeypot and
   non-disclosing-suppression preconditions. No explicit `consent` parameter exists
   on the package signature today — the fixture's `consent` field is target contract,
   not a claim that road-blogger's endpoint already accepts it. `api/modules/subscriber`
   exists as the live ORDS module this baseline is drawn from.
7. No target file exists and no competing root-level validation convention exists.
   Clear to proceed to the Action step below, pending sign-off.

## Action

Create exactly these files using the appendices:

1. `spec/governed-state-contract.schema.json`
2. `test/contract/fixtures/governed-state-contract.valid.json`
3. `test/contract/validate-governed-state-contract-schema.mjs`

Run only the W1 Node test command. Do not run SQL, deploy to ORDS, obtain a token,
connect to a database, or create a Git tag until all acceptance criteria have passed
and Simon approves the release.

## Out of scope

- MCP descriptor generation or MCP server configuration (W2).
- ORDS modules, handlers, privileges, JWT changes, PL/SQL packages, tables,
  sequences, triggers, or audit implementation (W3).
- Proposal endpoint implementation beyond the newsletter subscription-request
  fixture.
- The v1 microsite schema page or any automatic site generation.
- A schema registry, package publication, npm dependency, or new root-level package
  manifest.
- OpenAPI generation. The W1 schema is the contract's behavioural core; an OpenAPI
  projection is a later consumer-facing decision.
- Changing existing ROAD API, error, security, deployment, or testing standards.

## Baseline and target distinction

ROAD Blogger is evidence for this lifecycle, not a claim that this W1 contract
already exists in that codebase. Its browser currently enforces consent before
submission but does not send an explicit `consent` field to the endpoint; its
implementation queues confirmation email rather than exposing a formal
emitted-event contract. W1 records the target contract that a later W3
implementation must satisfy. It makes no change to ROAD Blogger.

## Acceptance checklist

- [ ] Discovery findings reported; no target file was overwritten.
- [ ] The schema parses as JSON and declares JSON Schema Draft 2020-12 and semantic
      version `0.1.0`.
- [ ] The schema requires an identifier, title, action resource, authority, request,
      preconditions, outcomes, audit, and events.
- [ ] The schema makes structured rejection explicit, including a stable
      machine-readable code and retryability, while permitting a privacy-preserving
      accepted response where revealing state would leak information.
- [ ] The representative fixture expresses a proposal — not direct mutation —
      through ROAD Blogger's `POST /subscribe` flow. It includes natural-key
      idempotency by normalised email, consent, a current-state re-read, audit, and
      an emitted confirmation-queue event.
- [ ] Honeypot and suppressed-email outcomes remain publicly indistinguishable from
      an accepted subscription request.
- [ ] `node test/contract/validate-governed-state-contract-schema.mjs` passes
      without installing dependencies.
- [ ] `git diff --check` passes; `git diff` shows only the three intended files.
- [ ] No SQL, ORDS, or remote deployment command was run.
- [ ] After Simon approves release: create and push annotated tag `v0.1.0`; record
      the tag in the cross-repository evidence interface (`road-atlas`). A later
      website action may cite it where relevant.

## Appendix A — `spec/governed-state-contract.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/simongriffiths/road-kit/blob/v0.1.0/spec/governed-state-contract.schema.json",
  "title": "Governed State Contract",
  "description": "A machine-readable definition of a governed business action. Consumers propose; the operational authority validates and decides.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version",
    "capability_id",
    "title",
    "action_resource",
    "authority",
    "request",
    "preconditions",
    "outcomes",
    "audit",
    "events"
  ],
  "properties": {
    "schema_version": {
      "const": "0.1.0"
    },
    "capability_id": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$",
      "description": "Stable identifier for the business capability."
    },
    "title": {
      "type": "string",
      "minLength": 1,
      "description": "Human-readable action name."
    },
    "description": {
      "type": "string",
      "minLength": 1
    },
    "action_resource": {
      "type": "object",
      "additionalProperties": false,
      "required": ["method", "path", "intent"],
      "properties": {
        "method": {
          "const": "POST",
          "description": "Governed actions are proposed using POST."
        },
        "path": {
          "type": "string",
          "pattern": "^/[^?]*$",
          "description": "Noun-based API resource path, without host or query string."
        },
        "intent": {
          "type": "string",
          "minLength": 1,
          "description": "The business intent the consumer is proposing."
        }
      }
    },
    "authority": {
      "type": "object",
      "additionalProperties": false,
      "required": ["operational_authority", "actor"],
      "properties": {
        "operational_authority": {
          "type": "string",
          "minLength": 1
        },
        "actor": {
          "type": "object",
          "additionalProperties": false,
          "required": ["model", "required_permissions", "attribution_required"],
          "properties": {
            "model": { "enum": ["public", "authenticated", "delegated"] },
            "required_permissions": {
              "type": "array",
              "items": { "type": "string", "minLength": 1 },
              "uniqueItems": true
            },
            "attribution_required": { "type": "boolean" }
          }
        }
      }
    },
    "request": {
      "type": "object",
      "additionalProperties": false,
      "required": ["idempotency", "body"],
      "properties": {
        "idempotency": {
          "type": "object",
          "additionalProperties": false,
          "required": ["strategy"],
          "properties": {
            "strategy": { "enum": ["idempotency_key", "natural_key"] },
            "header": { "type": "string", "minLength": 1 },
            "fields": {
              "type": "array",
              "minItems": 1,
              "items": { "type": "string", "minLength": 1 },
              "uniqueItems": true
            }
          },
          "allOf": [
            {
              "if": { "properties": { "strategy": { "const": "idempotency_key" } } },
              "then": { "required": ["header"] }
            },
            {
              "if": { "properties": { "strategy": { "const": "natural_key" } } },
              "then": { "required": ["fields"] }
            }
          ]
        },
        "body": {
          "type": "object",
          "description": "JSON Schema describing the proposed-action request body."
        }
      }
    },
    "preconditions": {
      "type": "object",
      "additionalProperties": false,
      "required": ["current_state_recheck", "rules"],
      "properties": {
        "current_state_recheck": {
          "const": true,
          "description": "The operational authority re-reads authoritative state at execution time."
        },
        "rules": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "description"],
            "properties": {
              "id": {
                "type": "string",
                "pattern": "^[A-Z][A-Z0-9_]*$"
              },
              "description": { "type": "string", "minLength": 1 }
            }
          },
          "uniqueItems": true
        }
      }
    },
    "outcomes": {
      "type": "object",
      "additionalProperties": false,
      "required": ["success", "rejections"],
      "properties": {
        "success": {
          "type": "object",
          "additionalProperties": false,
          "required": ["status", "description"],
          "properties": {
            "status": { "type": "integer", "minimum": 200, "maximum": 299 },
            "description": { "type": "string", "minLength": 1 }
          }
        },
        "rejections": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["code", "status", "description", "retryable"],
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[A-Z][A-Z0-9_]*$"
              },
              "status": { "type": "integer", "minimum": 400, "maximum": 499 },
              "description": { "type": "string", "minLength": 1 },
              "retryable": { "type": "boolean" }
            }
          },
          "uniqueItems": true
        }
      }
    },
    "audit": {
      "type": "object",
      "additionalProperties": false,
      "required": ["transactional", "fields"],
      "properties": {
        "transactional": {
          "const": true,
          "description": "The decision audit is written in the same transaction as any state change."
        },
        "fields": {
          "type": "array",
          "minItems": 1,
          "items": { "type": "string", "minLength": 1 },
          "uniqueItems": true
        }
      }
    },
    "events": {
      "type": "object",
      "additionalProperties": false,
      "required": ["emitted"],
      "properties": {
        "emitted": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["name", "when"],
            "properties": {
              "name": { "type": "string", "minLength": 1 },
              "when": { "const": "after_commit" }
            }
          },
          "uniqueItems": true
        }
      }
    }
  },
  "patternProperties": {
    "^x-": {}
  }
}
```

## Appendix B — `test/contract/fixtures/governed-state-contract.valid.json`

```json
{
  "schema_version": "0.1.0",
  "capability_id": "newsletter.subscription-request",
  "title": "Request newsletter subscription",
  "description": "Propose a double-opt-in newsletter subscription without disclosing whether an email address is active or suppressed.",
  "action_resource": {
    "method": "POST",
    "path": "/subscribe",
    "intent": "Request newsletter subscription"
  },
  "authority": {
    "operational_authority": "Subscriber Lifecycle",
    "actor": {
      "model": "public",
      "required_permissions": [],
      "attribution_required": false
    }
  },
  "request": {
    "idempotency": {
      "strategy": "natural_key",
      "fields": ["email"]
    },
    "body": {
      "type": "object",
      "additionalProperties": false,
      "required": ["email", "consent", "source_url"],
      "properties": {
        "email": { "type": "string", "format": "email" },
        "first_name": { "type": "string", "maxLength": 100 },
        "consent": { "const": true },
        "source_url": { "type": "string", "format": "uri" },
        "website": { "type": "string", "description": "Honeypot field; a populated value is silently accepted without creating a subscriber." }
      }
    }
  },
  "preconditions": {
    "current_state_recheck": true,
    "rules": [
      { "id": "VALID_EMAIL", "description": "The submitted email address is valid after normalisation." },
      { "id": "CONSENT_GIVEN", "description": "The reader has explicitly requested the newsletter." },
      { "id": "NOT_SUPPRESSED", "description": "The address is not on the suppression list; the public response remains non-disclosing if it is." },
      { "id": "SUBSCRIPTION_STATE_RECHECKED", "description": "Existing subscriber state is re-read before creating, reusing or confirming a pending request." }
    ]
  },
  "outcomes": {
    "success": {
      "status": 200,
      "description": "The request was accepted without disclosing whether a subscriber record was created, already existed, was suppressed or was rejected as automated traffic."
    },
    "rejections": [
      { "code": "INVALID_EMAIL", "status": 400, "description": "The supplied email address is invalid.", "retryable": true }
    ]
  },
  "audit": {
    "transactional": true,
    "fields": ["normalised_email", "consent_given", "signup_time", "signup_ip", "source_url", "decision", "resulting_state"]
  },
  "events": {
    "emitted": [
      { "name": "newsletter.confirmation-queued", "when": "after_commit" }
    ]
  }
}
```

## Appendix C — `test/contract/validate-governed-state-contract-schema.mjs`

```javascript
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const here = new URL('.', import.meta.url);
const schemaPath = fileURLToPath(new URL('../../spec/governed-state-contract.schema.json', here));
const fixturePath = fileURLToPath(new URL('./fixtures/governed-state-contract.valid.json', here));

const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
const fixture = JSON.parse(await readFile(fixturePath, 'utf8'));

assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
assert.equal(schema.properties.schema_version.const, '0.1.0');

for (const field of [
  'capability_id',
  'title',
  'action_resource',
  'authority',
  'request',
  'preconditions',
  'outcomes',
  'audit',
  'events'
]) {
  assert.ok(schema.required.includes(field), `schema must require ${field}`);
}

assert.equal(schema.properties.action_resource.properties.method.const, 'POST');
assert.ok(schema.properties.request.properties.idempotency.properties.strategy.enum.includes('natural_key'));
assert.equal(schema.properties.preconditions.properties.current_state_recheck.const, true);
assert.equal(schema.properties.outcomes.properties.rejections.items.properties.retryable.type, 'boolean');
assert.equal(schema.properties.audit.properties.transactional.const, true);
assert.equal(schema.properties.events.properties.emitted.items.properties.when.const, 'after_commit');

assert.equal(fixture.schema_version, '0.1.0');
assert.equal(fixture.capability_id, 'newsletter.subscription-request');
assert.equal(fixture.action_resource.method, 'POST');
assert.equal(fixture.action_resource.path, '/subscribe');
assert.equal(fixture.authority.actor.model, 'public');
assert.equal(fixture.request.idempotency.strategy, 'natural_key');
assert.deepEqual(fixture.request.idempotency.fields, ['email']);
assert.equal(fixture.request.body.properties.consent.const, true);
assert.equal(fixture.preconditions.current_state_recheck, true);
assert.equal(fixture.audit.transactional, true);
assert.ok(fixture.outcomes.rejections.some((outcome) => outcome.retryable));
assert.ok(fixture.outcomes.rejections.some((outcome) => outcome.code === 'INVALID_EMAIL'));
assert.ok(fixture.events.emitted.every((event) => event.when === 'after_commit'));

console.log('[PASS] Governed State Contract schema v0.1.0 structure and fixture verified');
```

## Files changed (summary)

1. `spec/governed-state-contract.schema.json` — canonical v0.1.0 behavioural contract
   schema.
2. `test/contract/fixtures/governed-state-contract.valid.json` — ROAD Blogger
   newsletter-subscription proposal fixture exercising the schema's required
   concepts.
3. `test/contract/validate-governed-state-contract-schema.mjs` — dependency-free
   structural regression test for the schema and fixture.
