#!/usr/bin/env node
// Every deployed handler is in the contract, and every contract entry has a handler (definition
// 9.5; spec-patch-16 section 3.5). Also checks that the contract version in the file, the one the
// database holds in ROAD_CONTRACT, the one inside the document it serves, and the one the framework
// stamps on responses (road_surface_api.contract_version, which reads the table) agree.
//
//   node test/contract/check-contract-coverage.mjs [--env dev] [contract/<app>.gsc.json]
//
// Reads the deployed surface through bin/run-sql.sh (test/contract/read-deployed-surface.sql),
// which only reads. The merged contract is used: the file plus the framework fragments it includes.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolveContract } from '../../scripts/lib/contract-merge.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const envIdx = args.indexOf('--env');
const env = envIdx >= 0 ? args[envIdx + 1] : 'dev';
const positional = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--env');
const appName = /^APP_NAME=(.+)$/m.exec(fs.readFileSync(path.join(root, 'road.config'), 'utf8'))?.[1].trim();
const contractFile = path.resolve(positional[0] ?? path.join(root, 'contract', `${appName}.gsc.json`));

// Deployed routes the contract does not describe, and why. Public and framework endpoints sit
// outside the governed surface; each needs a reason, because an entry here is the one way a
// handler escapes the check. The first path segment, under /api/v1.
const OUTSIDE = new Map([
  ['health', 'liveness probe, answers before anyone can sign in'],
  ['jwt-auth', 'the login and JWKS endpoints: a session cannot be required to get a session'],
  ['api-auth', 'agent sign-in: trades an API key for a token, so it cannot require one'],
  ['ui', 'static single-page-app assets'],
  ['admin', 'road_admin_api predates the definition; its conversion is its own patch (spec-patch-16 6.5)'],
]);

execFileSync(path.join(root, 'bin', 'run-sql.sh'),
  ['--env', env, '--script', 'test/contract/read-deployed-surface.sql'], { cwd: root, stdio: 'ignore' });
const runs = path.join(root, 'logs', env, 'runs');
const log = fs.readdirSync(runs).filter((f) => f.includes('read-deployed-surface'))
  .map((f) => path.join(runs, f)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
const lines = fs.readFileSync(log, 'utf8').split('\n').map((l) => l.trimEnd());

// /api/v1/items/ + :id/claims/:claim_id/ -> /items/{id}/claims/{claim_id}/
const norm = (p) => p.replace(/^\/api\/v1/, '').replace(/\/+/g, '/').replace(/:([a-z_]+)/g, '{$1}');
const deployed = new Map();
const outside = new Map();
for (const l of lines.filter((x) => x.startsWith('HANDLER|'))) {
  const [, method, prefix, template] = l.split('|');
  const p = norm(prefix + (template === '/' ? '' : template));
  const segment = p.split('/')[1];
  if (OUTSIDE.has(segment)) outside.set(`${method} ${p}`, OUTSIDE.get(segment));
  else deployed.set(`${method} ${p}`, true);
}
const stored = lines.find((l) => l.startsWith('STORED|'))?.split('|')[1]?.trim();
const served = lines.find((l) => l.startsWith('SERVED|'))?.split('|')[1]?.trim();

const { contract } = resolveContract(contractFile);
const declared = new Map();
for (const a of contract.state?.actions ?? []) declared.set(`${a.action_resource.rest.method} ${a.action_resource.rest.path}`, a.id);
for (const v of contract.publication?.views ?? []) declared.set(`${v.resource.rest.method} ${v.resource.rest.path}`, v.id);
const d = contract.envelope.versioning.discovery.rest;
declared.set(`${d.method} ${d.path}`, 'contract discovery');

const failures = [];
for (const [k, id] of declared) if (!deployed.has(k)) failures.push(`${id} (${k}) is in the contract but has no deployed handler`);
for (const k of deployed.keys()) if (!declared.has(k)) failures.push(`${k} is deployed but is not in the contract`);
const v = contract.envelope.contract_version;
if (stored !== v) failures.push(`the database holds contract ${stored}, the file has ${v}: run scripts/contract-to-sql.mjs and redeploy`);
if (served !== v) failures.push(`the document the database serves says ${served}, the file has ${v}`);

if (failures.length) {
  for (const f of failures) console.error(`[FAIL] ${f}`);
  process.exit(1);
}
console.log(`[PASS] ${deployed.size} deployed handlers match the ${declared.size} contract entries; contract ${v} in the file, the table and the served document`);
console.log(`[INFO] ${outside.size} handlers are outside the surface: ${[...new Set(outside.values())].length} reasons (${[...OUTSIDE.keys()].join(', ')})`);
