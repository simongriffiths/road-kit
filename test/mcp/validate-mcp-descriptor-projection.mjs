import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { projectMcpDescriptor } from '../../scripts/project-mcp-descriptor.mjs';

const here = new URL('.', import.meta.url);
const fixturePath = fileURLToPath(new URL('../contract/fixtures/governed-state-contract.valid.json', here));
const contract = JSON.parse(await readFile(fixturePath, 'utf8'));

const first = projectMcpDescriptor(contract);
const second = projectMcpDescriptor(contract);

// Determinism: repeated projection of the same contract is byte-identical.
assert.equal(JSON.stringify(first), JSON.stringify(second));

// Preserved and transformed.
assert.equal(first.name, 'newsletter_subscription_request');
assert.equal(first.description, contract.title);
assert.equal(first.inputSchema.type, contract.request.body.type);
assert.equal(first.inputSchema.additionalProperties, contract.request.body.additionalProperties);
assert.deepEqual(first.inputSchema.required, ['email', 'consent', 'source_url']);
assert.ok('email' in first.inputSchema.properties);
assert.ok('consent' in first.inputSchema.properties);
assert.ok('source_url' in first.inputSchema.properties);

// The descriptor carries exactly these three top-level fields.
assert.deepEqual(Object.keys(first).sort(), ['description', 'inputSchema', 'name']);

// Deliberately excluded: fields governing the decision, not the proposal.
const serialized = JSON.stringify(first);
for (const field of [
  'action_resource',
  'authority',
  'preconditions',
  'outcomes',
  'audit',
  'events',
  'schema_version',
  'capability_id'
]) {
  assert.ok(!serialized.includes(`"${field}"`), `descriptor must not leak ${field}`);
}

// The honeypot field, and any hint that it exists, must not reach the descriptor.
assert.ok(!('website' in first.inputSchema.properties), 'honeypot field must not appear in inputSchema');
assert.ok(!serialized.includes('Honeypot'), 'honeypot description must not leak');
assert.ok(!serialized.includes('honeypot'), 'honeypot description must not leak');

console.log('[PASS] MCP descriptor projection is deterministic and excludes governed-only fields');
