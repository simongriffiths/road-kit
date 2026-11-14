import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { checkContract, loadSchema } from '../../scripts/validate-gsc-contract.mjs';
import { validate } from '../../scripts/lib/json-schema-subset.mjs';

const here = new URL('.', import.meta.url);
const fixture = JSON.parse(await readFile(
  fileURLToPath(new URL('./fixtures/governed-surface-contract.valid.json', here)), 'utf8'));
const schema = await loadSchema();

assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
assert.equal(schema.properties.schema_version.const, '0.3.0');
assert.equal(schema.properties.gsc_definition_version.const, '0.1.0');

// The valid fixture passes.
assert.deepEqual(checkContract(schema, fixture), []);

// Each case breaks one requirement and must be refused. A schema that accepted everything would
// pass the check above, so these are what give it meaning.
const claim = (contract) => contract.state.actions.find((action) => action.id === 'items.claim');
const cases = [
  ['v0.1.0 rejection status (definition A.2: rejections are 200)',
    (c) => { claim(c).outcomes.rejections[0].status = 409; }, 'unexpected property "status"'],
  ['v0.1.0 rejection code in place of rule_id',
    (c) => { const r = claim(c).outcomes.rejections[0]; r.code = r.rule_id; delete r.rule_id; },
    'missing required "rule_id"'],
  ['delegated actor model (definition 5.2.6)',
    (c) => { claim(c).authority.actor.model = 'delegated'; }, 'must be one of'],
  ['identity taken from the request body (5.2.1)',
    (c) => { c.envelope.identity.established_from = ['request_body']; }, 'must be one of'],
  ['a change to an existing record with no concurrency check (6.6)',
    (c) => { claim(c).preconditions.rules = claim(c).preconditions.rules.filter((r) => r.kind !== 'concurrency');
             claim(c).outcomes.rejections = claim(c).outcomes.rejections.filter((r) => r.rule_id !== 'STALE_TOKEN'); },
    'contains no item'],
  ['decision record without the idempotency key (6.7.2)',
    (c) => { claim(c).audit.fields = claim(c).audit.fields.filter((f) => f !== 'idempotency_key'); },
    'contains no item'],
  ['an event before commit (6.8.1)',
    (c) => { claim(c).events.emitted[0].when = 'before_commit'; }, 'must equal "after_commit"'],
  ['a contract with neither section (5.1)',
    (c) => { delete c.state; delete c.publication; }, 'matches none of anyOf'],
  ['publication section not marked provisional',
    (c) => { delete c.publication.provisional; }, 'missing required "provisional"'],
  ['view with access rules but no scope statement (7.4.1)',
    (c) => { delete c.publication.views[0].scope.statement_field; }, 'missing required "statement_field"'],
  ['view with no time declaration (7.3)',
    (c) => { delete c.publication.views[0].time; }, 'missing required "time"'],
  ['a rejection that names no declared rule',
    (c) => { claim(c).outcomes.rejections.push({ rule_id: 'UNDECLARED', retryable: false }); },
    'is not a declared precondition rule'],
  ['a batch operation that is not a declared action (6.9.1)',
    (c) => { c.state.batch.operations.push('items.close'); }, 'is not a declared action'],
  ['a read token accepted by an undeclared action',
    (c) => { c.publication.views[0].read_tokens.changed_by.push('items.move'); }, 'is not a declared action'],
  ['a public action missing from public_entries (5.2.7)',
    (c) => { claim(c).authority.actor.model = 'public'; }, 'does not list it in public_entries'],
  ['a non-disclosing action with consumer-visible rules (9.3.3)',
    (c) => { claim(c).outcomes.non_disclosing = true; }, 'may not mark rules consumer_visible'],
  ['a duplicate id across sections',
    (c) => { c.publication.views[0].id = 'items.claim'; }, 'duplicate id "items.claim"'],
  ['an unknown top-level property',
    (c) => { c.capabilities = []; }, 'unexpected property "capabilities"']
];

for (const [name, mutate, expected] of cases) {
  const contract = structuredClone(fixture);
  mutate(contract);
  const problems = checkContract(schema, contract);
  assert.ok(problems.some((problem) => problem.includes(expected)),
    `${name}: expected a problem containing "${expected}", got ${JSON.stringify(problems)}`);
}

// Extension properties are allowed where the definition allows them (9.1.4).
const extended = structuredClone(fixture);
extended['x-owner'] = 'road-kit';
claim(extended)['x-notes'] = 'extension';
assert.deepEqual(checkContract(schema, extended), []);

// The validator refuses a keyword it does not implement, rather than skipping it.
assert.throws(() => validate({ type: 'string', format: 'email', dependentRequired: {} }, 'x'),
  /not supported/);

console.log(`[PASS] Governed Surface Contract schema 0.3.0: valid fixture accepted, ${cases.length} invalid variants refused`);
