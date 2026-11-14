#!/usr/bin/env node
// Validates a Governed Surface Contract document against
// spec/governed-surface-contract.schema.json, then checks the cross-references JSON Schema
// cannot express. Dependency-free.
//
//   node scripts/validate-gsc-contract.mjs path/to/surface.gsc.json
//
// Exit 0 when valid; exit 1 with one line per problem otherwise.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { validate } from './lib/json-schema-subset.mjs';

const schemaUrl = new URL('../spec/governed-surface-contract.schema.json', import.meta.url);

export async function loadSchema() {
  return JSON.parse(await readFile(fileURLToPath(schemaUrl), 'utf8'));
}

// Returns a list of problems; empty when the contract is valid.
export function checkContract(schema, contract) {
  const problems = validate(schema, contract);
  if (problems.length > 0) return problems;

  const actions = contract.state?.actions ?? [];
  const views = contract.publication?.views ?? [];
  const actionIds = new Set(actions.map((action) => action.id));

  // Identifiers are unique within the surface, across both sections (definition 6.2, 7.2).
  const seen = new Set();
  for (const entry of [...actions, ...views]) {
    if (seen.has(entry.id)) problems.push(`duplicate id "${entry.id}"`);
    seen.add(entry.id);
  }

  // One REST resource answers to one entry.
  const routes = new Set();
  const route = (rest) => rest && `${rest.method} ${rest.path}`;
  for (const entry of actions) {
    const key = route(entry.action_resource.rest);
    if (key && routes.has(key)) problems.push(`duplicate REST resource ${key}`);
    if (key) routes.add(key);
  }
  for (const entry of views) {
    const key = route(entry.resource.rest);
    if (key && routes.has(key)) problems.push(`duplicate REST resource ${key}`);
    if (key) routes.add(key);
  }

  for (const action of actions) {
    const ruleIds = new Set(action.preconditions.rules.map((rule) => rule.id));
    if (ruleIds.size !== action.preconditions.rules.length) {
      problems.push(`${action.id}: duplicate rule id in preconditions`);
    }
    // Every rejection names a declared rule (definition 6.2, 8.4.2).
    for (const rejection of action.outcomes.rejections) {
      if (!ruleIds.has(rejection.rule_id)) {
        problems.push(`${action.id}: rejection ${rejection.rule_id} is not a declared precondition rule`);
      }
    }
    // A non-disclosing action must not let a generated tool show its rules (definition 9.3.3).
    if (action.outcomes.non_disclosing
        && action.preconditions.rules.some((rule) => rule.consumer_visible)) {
      problems.push(`${action.id}: a non-disclosing action may not mark rules consumer_visible`);
    }
  }

  const batch = contract.state?.batch;
  for (const id of batch?.operations ?? []) {
    if (!actionIds.has(id)) problems.push(`batch: operation "${id}" is not a declared action`);
  }

  for (const view of views) {
    for (const id of view.read_tokens?.changed_by ?? []) {
      if (!actionIds.has(id)) {
        problems.push(`${view.id}: read token changed_by "${id}" is not a declared action`);
      }
    }
  }

  // Public entries are listed once in the envelope, and agree with their own actor model.
  const declaredPublic = new Set(contract.envelope.public_entries ?? []);
  for (const entry of [...actions, ...views]) {
    const isPublic = entry.authority.actor.model === 'public';
    if (isPublic && !declaredPublic.has(entry.id)) {
      problems.push(`${entry.id}: actor model is public but the envelope does not list it in public_entries`);
    }
    if (!isPublic && declaredPublic.has(entry.id)) {
      problems.push(`${entry.id}: listed in public_entries but its actor model is not public`);
    }
    declaredPublic.delete(entry.id);
  }
  for (const id of declaredPublic) problems.push(`public_entries: "${id}" is not a declared action or view`);

  return problems;
}

async function main() {
  const file = process.argv[2];
  if (!file) {
    process.stderr.write('Usage: node scripts/validate-gsc-contract.mjs <contract.json>\n');
    process.exit(2);
  }
  const contract = JSON.parse(await readFile(file, 'utf8'));
  const problems = checkContract(await loadSchema(), contract);
  if (problems.length > 0) {
    for (const problem of problems) process.stderr.write(`[FAIL] ${problem}\n`);
    process.exit(1);
  }
  process.stdout.write(`[PASS] ${file} is a valid Governed Surface Contract ` +
    `(schema ${contract.schema_version}, contract ${contract.envelope.contract_version})\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
