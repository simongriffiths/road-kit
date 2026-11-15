#!/usr/bin/env node
// Checks the outcome of bin/run-skill-acceptance.sh through the API, as the agent: the todo the
// session was asked to finish is done, the one it was asked to add twice exists once and is open,
// and the session's own report names the rule that refused the second add. Needs ROAD_CLI_HOME (the
// agent's signed-in home), ACC_STAMP, and ACC_RESULT (the file holding the session's final text).
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const cli = path.join(root, 'tools', 'road-cli', 'road-cli');
const stamp = process.env.ACC_STAMP;
let pass = 0;
let fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`[PASS] ${label}`); } else { fail++; console.log(`[FAIL] ${label}${detail ? ` -- ${JSON.stringify(detail).slice(0, 400)}` : ''}`); }
};
const api = (p) => JSON.parse(spawnSync(cli, ['api', 'GET', p], { encoding: 'utf8', env: process.env }).stdout || '{}');

const done = api('/todos/?status=DONE').items ?? [];
const open = api('/todos/?status=OPEN').items ?? [];
const answer = fs.existsSync(process.env.ACC_RESULT ?? '') ? fs.readFileSync(process.env.ACC_RESULT, 'utf8') : '';
check('the stamps todo is done', done.some((t) => t.title === `Order stamps ${stamp}`), done.map((t) => t.title));
check('the van todo exists once, and is open', open.filter((t) => t.title === `Book the van ${stamp}`).length === 1, open.map((t) => t.title));
check('nothing else was added', open.length + done.length === 2, { open: open.length, done: done.length });
check('the report names the rule that refused the second add', answer.includes('TITLE_TAKEN'), answer.slice(0, 300));
console.log(`[INFO] skill acceptance checks: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
