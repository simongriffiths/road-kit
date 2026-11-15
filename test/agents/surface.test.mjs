#!/usr/bin/env node
// The governed todo surface over HTTP (spec-patch-16 section 5), run by bin/run-agent-tests.sh with
// tokens it mints for fixture people. Proves what only HTTP can: GET /contract/ is public and is the
// contract; Accept-Version; the contract version on every body, errors included; decisions answer
// 200 with rule_id and audit_id; replays; staleness leaves no change; a hidden todo looks missing;
// the standard fields on views. The PL/SQL suites cover each rule; this covers the layer between.
// Needs ORDS_BASE_URL, TOKEN_USER1, TOKEN_OTHER.

const base = process.env.ORDS_BASE_URL;
const tok = (who) => process.env[`TOKEN_${who}`];
let pass = 0;
let fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`[PASS] ${label}`); } else { fail++; console.log(`[FAIL] ${label}${detail ? ` -- ${JSON.stringify(detail).slice(0, 300)}` : ''}`); }
};
const stamp = Date.now();
let seq = 0;
const key = () => `surface-${stamp}-${++seq}`;
async function call(method, path, who, { body, idem, headers = {} } = {}) {
  const h = { ...(who ? { Authorization: `Bearer ${tok(who)}` } : {}), ...headers };
  if (body !== undefined) h['Content-Type'] = 'application/json';
  if (idem) h['Idempotency-Key'] = idem;
  const res = await fetch(`${base}${path}`, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, json };
}

// --- discovery: public, and it is the contract
let r = await call('GET', '/contract/', null);
const version = r.json?.envelope?.contract_version;
check('GET /contract/ needs no token and serves the contract', r.status === 200 && version && r.json?.surface?.id === 'hello_world', { status: r.status });
check('the contract includes the framework fragments (agents, session)',
  r.json?.state?.actions?.some((a) => a.id === 'agents.create') && r.json?.publication?.views?.some((v) => v.id === 'session.me'));

// --- the version on a request, and on every answer
r = await call('GET', '/todos/', 'USER1', { headers: { 'Accept-Version': '99' } });
check('another major Accept-Version: 400 VERSION_MISMATCH with the version', r.status === 400 && r.json?.error === 'VERSION_MISMATCH' && r.json?.contract_version === version, r.json);
r = await call('GET', '/todos/', 'USER1', { headers: { 'Accept-Version': '0' } });
check('the same major Accept-Version is served', r.status === 200, r.status);

// --- create, replay, wrong calls, a rule
const title = `surface ${stamp}`;
r = await call('POST', '/todos/', 'USER1', { body: { title }, idem: key() });
const first = r;
const id = r.json?.result?.todo_id;
check('create: 200 accepted, with the version and an audit id', r.status === 200 && r.json?.decision === 'accepted' && r.json?.contract_version === version && Number.isInteger(r.json?.audit_id) && id, r.json);
const k = key();
const a = await call('POST', '/todos/', 'USER1', { body: { title: `${title} replay` }, idem: k });
const b = await call('POST', '/todos/', 'USER1', { body: { title: `${title} replay` }, idem: k });
check('the same Idempotency-Key replays the same decision', a.json?.audit_id && a.json.audit_id === b.json?.audit_id, { a: a.json?.audit_id, b: b.json?.audit_id });
r = await call('POST', '/todos/', 'USER1', { body: { title: 'forged', owner_principal_id: 1 }, idem: key() });
check('a named owner is a 400 that still states the version', r.status === 400 && r.json?.error === 'VALIDATION_ERROR' && r.json?.contract_version === version, r.json);
r = await call('POST', '/todos/', 'USER1', { body: { title: 'no key' } });
check('no Idempotency-Key: 400 with the version', r.status === 400 && r.json?.contract_version === version, r.json);
r = await call('POST', '/todos/', 'USER1', { body: { title }, idem: key() });
check('a rule: 200 rejected with rule_id, ids and an audit id', r.status === 200 && r.json?.decision === 'rejected' && r.json?.rejections?.[0]?.rule_id === 'TITLE_TAKEN' && r.json?.rejections?.[0]?.ids?.[0] === id && r.json?.audit_id, r.json);

// --- views carry the standard fields
r = await call('GET', '/todos/', 'USER1');
const listToken = r.json?.read_token;
check('list: version, as_at, scope and a read token', r.status === 200 && r.json?.contract_version === version && r.json?.as_at && r.json?.scope && listToken, r.json && Object.keys(r.json));
check('list holds the todo', r.json?.items?.some((t) => t.todo_id === id));
r = await call('GET', `/todos/${id}/`, 'USER1');
const token = r.json?.read_token;
check('get: the todo with a read token and the standard fields', r.status === 200 && r.json?.todo?.todo_id === id && token && r.json?.as_at && r.json?.contract_version === version, r.json);

// --- staleness leaves no change; a re-read then works
r = await call('POST', `/todos/${id}/revisions/`, 'USER1', { body: { read_token: token, title: `${title} revised` } });
check('revise with a fresh token: accepted', r.json?.decision === 'accepted' && r.json?.result?.read_token, r.json);
const next = r.json?.result?.read_token;
// The list's token was issued before the revision above, so it is stale for this todo. (The same
// token and todo again would replay the first answer: that is the natural idempotency key.)
r = await call('POST', `/todos/${id}/revisions/`, 'USER1', { body: { read_token: listToken, title: 'stale write' } });
check('a token from before the change is stale: 200 rejected STALE_TOKEN, retryable', r.status === 200 && r.json?.rejections?.[0]?.rule_id === 'STALE_TOKEN' && r.json?.rejections?.[0]?.retryable === true, r.json);
r = await call('GET', `/todos/${id}/`, 'USER1');
check('and nothing changed', r.json?.todo?.title === `${title} revised`, r.json?.todo?.title);
r = await call('POST', `/todos/${id}/revisions/`, 'USER1', { body: { read_token: token, title: `${title} revised` } });
check('the same token and todo again replays the accepted answer', r.json?.decision === 'accepted', r.json);
r = await call('POST', `/todos/${id}/revisions/`, 'USER1', { body: { title: 'no token' } });
check('no read token: 400 with the version', r.status === 400 && r.json?.contract_version === version, r.json);

// --- the cycle, with the token an action returns
r = await call('POST', `/todos/${id}/completions/`, 'USER1', { body: { read_token: next } });
check('complete', r.json?.decision === 'accepted' && r.json?.result?.status === 'DONE', r.json);
const done = r.json?.result?.read_token;
r = await call('POST', `/todos/${id}/revisions/`, 'USER1', { body: { read_token: done, title: 'x' } });
check('revise a done todo: TODO_DONE', r.json?.rejections?.[0]?.rule_id === 'TODO_DONE', r.json);
r = await call('POST', `/todos/${id}/reopenings/`, 'USER1', { body: { read_token: done } });
check('reopen', r.json?.decision === 'accepted' && r.json?.result?.status === 'OPEN', r.json);

// --- another person: a hidden todo looks missing
r = await call('GET', `/todos/${id}/`, 'OTHER');
check('another person\'s GET: 404 with the version', r.status === 404 && r.json?.contract_version === version, r.json);
r = await call('POST', `/todos/${id}/completions/`, 'OTHER', { body: { read_token: token } });
const hidden = r.json;
r = await call('POST', '/todos/999999999/completions/', 'OTHER', { body: { read_token: token } });
check('and an action on it is refused exactly as a missing todo is', hidden?.rejections?.[0]?.rule_id === 'TODO_NOT_FOUND' && r.json?.rejections?.[0]?.rule_id === 'TODO_NOT_FOUND' && hidden.rejections[0].message === r.json.rejections[0].message && !hidden.rejections[0].ids, { hidden, missing: r.json });

// --- delete, and the reserved purge
const view = await call('GET', `/todos/${id}/`, 'USER1');
r = await call('DELETE', `/todos/${id}/`, 'USER1', { body: { read_token: view.json?.read_token } });
check('delete: accepted', r.json?.decision === 'accepted', r.json);
r = await call('GET', `/todos/${id}/`, 'USER1');
check('a deleted todo is 404', r.status === 404, r.status);
r = await call('POST', '/todos/purges/', 'USER1', { body: { before: '2999-01-01T00:00:00Z' }, idem: key() });
check('an ordinary user cannot purge: 403 with the version', r.status === 403 && r.json?.contract_version === version, r.json);

// --- the session view
r = await call('GET', '/session/me/', 'USER1');
check('session.me carries the version and as_at', r.status === 200 && r.json?.contract_version === version && r.json?.as_at && r.json?.principal_id, r.json && Object.keys(r.json));

console.log(`[INFO] governed surface over HTTP: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
