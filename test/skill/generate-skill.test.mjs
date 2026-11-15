#!/usr/bin/env node
// Tests scripts/generate-skill.mjs (spec-patch-15 section 4.8) against road-kit's own contract
// fixture, with a commands file and config made in a temporary folder. Proves: it writes a skill
// that names the contract version and the rules of the commands' actions; --check passes, then
// fails once the file is edited; a rule marked consumer_visible: false is left out; and it refuses
// a command mapped to a resource the contract lacks, or one the agent role may not use.
//
//   node test/skill/generate-skill.test.mjs

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'test/contract/fixtures/governed-surface-contract.valid.json'), 'utf8'));
let pass = 0;
let fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`[PASS] ${label}`); } else { fail++; console.log(`[FAIL] ${label}${detail ? ` -- ${String(detail).slice(0, 300)}` : ''}`); }
};

function setup({ calls, perms, contract = fixture }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'skill-'));
  fs.writeFileSync(path.join(dir, 'contract.json'), JSON.stringify(contract));
  fs.writeFileSync(path.join(dir, 'commands.mjs'), `export default { calls: ${JSON.stringify(calls)} };\n// calls /items and /claims\n`);
  fs.writeFileSync(path.join(dir, 'skill.config.mjs'), `export default {
  name: 'fixture', description: 'A fixture skill.', cli: 'fx',
  contract: ${JSON.stringify(path.join(dir, 'contract.json'))},
  commands: ${JSON.stringify(path.join(dir, 'commands.mjs'))},
  agentPermissions: ${JSON.stringify(perms)},
  workflow: '## Work\\n\\n1. \`fx claim ID\`.',
};\n`);
  return dir;
}
const gen = (dir, check) => spawnSync('node', [path.join(root, 'scripts/generate-skill.mjs'), path.join(dir, 'skill.config.mjs'), ...(check ? ['--check'] : [])], { encoding: 'utf8', cwd: root });

const perms = ['item.create', 'item.claim', 'item.read'];
let dir = setup({ calls: { claim: ['POST /items/{id}/claims'], add: ['POST /items'] }, perms });
let r = gen(dir);
const skill = fs.existsSync(path.join(dir, 'SKILL.md')) ? fs.readFileSync(path.join(dir, 'SKILL.md'), 'utf8') : '';
check('writes a skill naming the contract version', r.status === 0 && skill.includes(fixture.envelope.contract_version), r.stderr);
const claimRules = fixture.state.actions.find((a) => a.id === 'items.claim').preconditions.rules.filter((x) => x.id !== 'STALE_TOKEN');
check('with the rules of the commands\' actions', claimRules.every((x) => skill.includes(`\`${x.id}\``)), claimRules.map((x) => x.id));
check('and the workflow', skill.includes('`fx claim ID`'));
r = gen(dir, true);
check('--check passes on what it wrote', r.status === 0, r.stderr);
fs.appendFileSync(path.join(dir, 'SKILL.md'), 'edited by hand\n');
r = gen(dir, true);
check('--check fails once it is edited', r.status === 1 && r.stderr.includes('not what the contract generates'), r.stderr);

const hidden = JSON.parse(JSON.stringify(fixture));
const hiddenRule = hidden.state.actions.find((a) => a.id === 'items.claim').preconditions.rules.find((x) => x.id !== 'STALE_TOKEN');
hiddenRule.consumer_visible = false;
dir = setup({ calls: { claim: ['POST /items/{id}/claims'] }, perms, contract: hidden });
r = gen(dir);
check('a rule marked consumer_visible: false is left out', r.status === 0 && !fs.readFileSync(path.join(dir, 'SKILL.md'), 'utf8').includes(`\`${hiddenRule.id}\``), r.stderr);

dir = setup({ calls: { nope: ['POST /items/{id}/nothing'] }, perms });
r = gen(dir);
check('a command mapped to a missing resource fails', r.status === 1 && r.stderr.includes('not in'), r.stderr);
dir = setup({ calls: { revise: ['POST /items/{id}/revisions'] }, perms });
r = gen(dir);
check('a command the agent role may not use fails', r.status === 1 && r.stderr.includes('may not use'), r.stderr);

console.log(`[INFO] generate-skill: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
