#!/usr/bin/env node
// tools/road-cli against the dev schema (spec-patch-15), run by bin/run-agent-tests.sh. USER1 makes
// an agent and a key over HTTP; road-cli signs in with it in a private temporary home and works
// todos with the demo's commands; then the key is revoked and road-cli is shut out. The key goes
// from the API answer to road-cli's standard input and is never printed.
// Needs ORDS_BASE_URL and TOKEN_USER1.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const CLI = path.join(root, 'tools', 'road-cli', 'road-cli');
const base = process.env.ORDS_BASE_URL;
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'road-cli-'));
fs.chmodSync(home, 0o700);
let pass = 0;
let fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`[PASS] ${label}`); } else { fail++; console.log(`[FAIL] ${label}${detail ? ` -- ${JSON.stringify(detail).slice(0, 300)}` : ''}`); }
};
const api = async (method, p, body, idem) => (await fetch(`${base}${p}`, {
  method, headers: { Authorization: `Bearer ${process.env.TOKEN_USER1}`, ...(body ? { 'Content-Type': 'application/json' } : {}), ...(idem ? { 'Idempotency-Key': idem } : {}) },
  body: body ? JSON.stringify(body) : undefined,
})).json();
const cli = (args, input) => {
  const r = spawnSync(CLI, args, { env: { ...process.env, ROAD_CLI_HOME: home }, input, encoding: 'utf8' });
  return { code: r.status, out: (r.stdout + r.stderr).trim() };
};

try {
  const stamp = Date.now();
  const agent = (await api('POST', '/agents/', { display_name: 'agent-test road-cli' }, `cli-a-${stamp}`)).result?.agent_id;
  const made = await api('POST', `/agents/${agent}/keys/`, { name: 'agent-test cli' }, `cli-k-${stamp}`);
  const secret = made.result?.api_key;

  let r = cli(['login', '--url', base], secret);
  check('login signs in as the agent', r.code === 0 && /^signed in as AGENT_\d+/.test(r.out), r);
  check('the key file is private', (fs.statSync(path.join(home, 'key')).mode & 0o077) === 0);
  r = cli(['whoami']);
  check('whoami', r.code === 0 && r.out.startsWith('AGENT_'), r);
  r = cli(['todo-add', `agent-test todo ${stamp}`]);
  const id = (r.out.match(/^added (\d+):/) || [])[1];
  check('todo-add', r.code === 0 && Boolean(id), r);
  r = cli(['todos']);
  check('todos lists it, one line each', r.code === 0 && r.out.includes(`agent-test todo ${stamp}`) && !r.out.includes('{'), r);
  r = cli(['todo-done', id]);
  check('todo-done reads it, then marks it done', r.code === 0 && r.out.startsWith(`${id} done:`), r);
  r = cli(['api', 'GET', `/todos/${id}/`]);
  check('api gives the raw JSON', r.code === 0 && JSON.parse(r.out).todo?.status === 'DONE', r.out.slice(0, 100));
  r = cli(['api', 'GET', '/agents/']);
  check('an agent cannot manage agents: exit 1', r.code === 1 && /not allowed|HTTP 40/.test(r.out), r);
  r = cli(['nonsense']);
  check('an unknown command: exit 2', r.code === 2, r);
  r = cli(['help']);
  check('help lists the core and the demo commands', r.code === 0 && r.out.includes('login') && r.out.includes('todo-done'), r.out.slice(0, 120));

  const list = await api('GET', '/agents/');
  const keyId = list.agents?.find((a) => a.agent_id === agent)?.keys?.[0]?.key_id;
  check('My agents shows the key was used, never the key', Boolean(list.agents?.find((a) => a.agent_id === agent)?.keys?.[0]?.last_used_at) && !JSON.stringify(list).includes(secret));
  await api('DELETE', `/agents/${agent}/keys/${keyId}/`, undefined, `cli-r-${stamp}`);
  fs.unlinkSync(path.join(home, 'token.json'));
  r = cli(['whoami']);
  check('a revoked key no longer signs in: exit 1', r.code === 1 && r.out.includes('revoked'), r);
} finally {
  fs.rmSync(home, { recursive: true, force: true });
}
console.log(`[INFO] road-cli: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
