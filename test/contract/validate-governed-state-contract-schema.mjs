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
