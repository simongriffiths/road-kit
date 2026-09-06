# Action File W2 — Deterministic MCP Descriptor Projection

**Status:** Ready for Simon's technical sign-off. Honeypot-exclusion decision made
2026-09-04 (option a, below). Do not execute until this file's release convention is
approved.

**Concern (single):** Build a deterministic, dependency-free projector that reads a
Governed State Contract (W1 schema, `schema_version` `0.1.0`) and emits an MCP tool
descriptor — `{ name, description, inputSchema }`, the shape `tools/list` returns per
the Model Context Protocol spec. Test stable, repeatable output from the W1
`newsletter.subscription-request` fixture. This action does not register a tool
against any MCP server (ADB's `DBMS_CLOUD_AI_AGENT` or otherwise), does not touch
road-blogger, and does not select W3's target domain.

## Discovery

1. W1 is released: `spec/governed-state-contract.schema.json` (tag `v0.1.0`, commit
   `44afcc6`), fixture at `test/contract/fixtures/governed-state-contract.valid.json`.
   Recorded cross-repo as `road-atlas` ledger `RK-10`.
2. No MCP tooling exists in road-kit yet. `planning/road-stack-build-lessons.md`
   (§"MCP tool servers on ADB Serverless") carries generalized findings from a
   road-cal spike (`road-cal/spec/spike-adb-mcp-server.md` /
   `spike-adb-mcp-findings.md`, parked repo) against Oracle's built-in
   `DBMS_CLOUD_AI_AGENT` MCP server. Two findings matter for what W2 must **not**
   assume about any future ADB-registered tool, even though W2 itself never touches
   ADB:
   - `CREATE_TOOL`'s generated `inputSchema` marks every parameter `required: true`
     regardless of the contract's own optionality, and the server enforces that.
     "Optional" has to be signalled to callers out-of-band (empty string convention),
     not through standard JSON Schema `required`.
   - Parameter name casing is not preserved — `tools/list` reports registered names
     uppercased regardless of how they were registered.
   W2's projector targets the generic MCP `inputSchema` shape only (which does respect
   `required` normally). Any ADB-specific re-shaping is out of scope here and belongs
   with whichever W3 domain actually registers against ADB's server.
3. No root-level `package.json` exists; W1's test stayed dependency-free
   (`node:assert`, `node:fs`). Same convention applies here — confirmed acceptable to
   Simon for this toolchain (2026-09-04).
4. `test/contract/` currently holds only W1's fixture and validator. A `test/mcp/`
   directory does not exist.

## Decision — resolved 2026-09-04

**The W1 fixture's `website` field is a honeypot, and its own description says so in
plain language** (`"Honeypot field; a populated value is silently accepted without
creating a subscriber."`). A mechanical projection of `request.body.properties` into
`inputSchema` would carry that description verbatim into the MCP tool descriptor —
which is read by any MCP client, including an adversarial one. That hands a bot exactly
the information the honeypot exists to withhold, over a channel (`tools/list`) that
W1 never anticipated.

Three ways to handle it, none free:

- **(a) Exclude honeypot-purpose fields from the generated `inputSchema`.** Needs a
  machine-readable way to mark a field as MCP-excluded. W1's schema already reserves
  `x-`-prefixed extension properties at the document root (`patternProperties: {"^x-":
  {}}`) but **not** inside `request.body`'s nested JSON Schema, which is
  `additionalProperties: false` at the object level but places no constraint on its
  own `properties.*` entries — so an `x-mcp-exclude` marker on a body property would
  validate fine against v0.1.0 as-is; nothing needs reopening. This is the option I'd
  default to, but it establishes a projection convention with no precedent, so I'm not
  calling it unilaterally.
- **(b) Project every body field mechanically, honeypot included.** Simplest, matches
  "deterministic" literally, but ships a live information leak the moment any contract
  with a honeypot goes through this path.
- **(c) Exclude by a fixed, hardcoded field-name convention** (e.g. any property
  literally named `website` or matching some hardcoded list) instead of a schema
  marker. Avoids touching W1's fixture but is fragile and not really "deterministic
  projection" so much as a special case.

**Decided: option (a).** Add `"x-mcp-exclude": true` to the fixture's `website`
property (a fixture change, not a schema change — W1's schema and its `v0.1.0` tag are
not reopened). The projector drops any `request.body.properties` entry carrying that
marker.

## Decisions carried by this action

- Projector path: `scripts/project-mcp-descriptor.mjs` (or `test/mcp/` if you'd rather
  keep it alongside the validator — open to either).
- `name`: derived deterministically from `capability_id` by replacing every `.` and
  `-` with `_` (MCP tool names are conventionally `[a-z0-9_]+`; `capability_id`
  permits `.` and `-`). `newsletter.subscription-request` → `newsletter_subscription_request`.
- `description`: contract `title`, falling back to `action_resource.intent` if
  `title` is absent (it isn't, in the W1 fixture, but the schema doesn't require them
  to match).
- `inputSchema`: `request.body` verbatim, minus any `x-mcp-exclude` properties (see
  above), with `additionalProperties: false` preserved.
- **Deliberately excluded from every projection** (these stay in the source contract,
  never reach the MCP descriptor): `action_resource.method`/`path` (the descriptor has
  no transport slot for them), `authority`, `preconditions`, `outcomes`, `audit`,
  `events`, `schema_version`, `capability_id` itself. The descriptor tells a caller
  *what it can propose*, not *how it will be decided* — that asymmetry is the point of
  a governed contract and should be stated as a test assertion, not just prose.
- Test: `test/mcp/validate-mcp-descriptor-projection.mjs`, dependency-free. Runs the
  projector against the W1 fixture twice and asserts byte-identical JSON output
  (determinism), then asserts the excluded-fields list above is genuinely absent from
  the result and that the honeypot field (however excluded) does not appear.

## Out of scope

- Registering a tool against any MCP server, ADB's or otherwise.
- Any change to the W1 schema or its `v0.1.0` tag.
- W3 (reference governed action) or W4 (end-to-end proof).
- OpenAPI or any non-MCP projection.

## Acceptance checklist (once approved)

- [ ] The fixture carries `x-mcp-exclude` on `website` with no other fixture content
      changed.
- [ ] Projector produces byte-identical output across repeated runs on the same input.
- [ ] Generated descriptor contains exactly `name`, `description`, `inputSchema` —
      nothing else.
- [ ] None of the deliberately-excluded contract fields appear anywhere in the output.
- [ ] Honeypot field does not appear in the generated `inputSchema`.
- [ ] `node test/mcp/validate-mcp-descriptor-projection.mjs` passes with no new
      dependency.
- [ ] `git diff --check` passes; diff shows only the intended files.
- [ ] Release convention mirrors W1: commit → run test → Simon approves → tag → record
      in road-atlas. Not executed until Simon signs off.
