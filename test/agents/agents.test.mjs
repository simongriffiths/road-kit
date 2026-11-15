#!/usr/bin/env node
// Agents and API keys over HTTP (spec-patch-15), run by bin/run-agent-tests.sh. USER1 makes an agent
// of its own and a key for it; the key buys a token at /api-auth/tokens; the agent is its own
// principal, holds only the demo's agent role, and works todos; another person cannot see it; ADMIN
// sees every agent and revokes; revoked and retired keys buy nothing. Keys are never printed.
// Needs ORDS_BASE_URL, AUTH_URL, TOKEN_USER1, TOKEN_ADMIN, TOKEN_OTHER.

const base = process.env.ORDS_BASE_URL;
const authUrl = process.env.AUTH_URL;
const tok = (who) => process.env[`TOKEN_${who}`];
let pass = 0;
let fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`[PASS] ${label}`); } else { fail++; console.log(`[FAIL] ${label}${detail ? ` -- ${JSON.stringify(detail).slice(0, 300)}` : ''}`); }
};
const key = (s) => `agent-test-${Date.now()}-${s}`;
async function call(method, path, who, { body, idem, bearer } = {}) {
  const headers = { Authorization: `Bearer ${bearer ?? tok(who)}` };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (idem) headers['Idempotency-Key'] = idem;
  const res = await fetch(`${base}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, json };
}
async function exchange(apiKey) {
  const res = await fetch(authUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(apiKey === undefined ? {} : { api_key: apiKey }) });
  return { status: res.status, json: await res.json().catch(() => null) };
}

let r = await call('POST', '/agents/', 'USER1', { body: { display_name: 'agent-test Claude Code' }, idem: key('a') });
check('a person makes an agent of their own: 200 accepted', r.status === 200 && r.json?.decision === 'accepted' && /^AGENT_\d+$/.test(r.json?.result?.subject ?? ''), r.json);
const agent = r.json?.result?.agent_id;
const subject = r.json?.result?.subject;
r = await call('POST', '/agents/', 'USER1', { body: { display_name: 'agent-test shared', shared: true }, idem: key('s') });
check('only a manager makes a shared agent: 403', r.status === 403, r.status);
r = await call('POST', '/agents/', 'USER1', { body: { display_name: 'x' } });
check('no Idempotency-Key: 400', r.status === 400, r.status);

r = await call('POST', `/agents/${agent}/keys/`, 'USER1', { body: { name: 'agent-test laptop' }, idem: key('k') });
const secret = r.json?.result?.api_key;
const keyId = r.json?.result?.key_id;
check('a key, shown once, with the prefix', r.json?.decision === 'accepted' && /^[a-z]+_[0-9a-f]{48}$/.test(secret ?? ''), { decision: r.json?.decision });
r = await call('GET', '/agents/', 'USER1');
const mine = r.json?.agents?.find((a) => a.agent_id === agent);
check('My agents lists it and its key, never the key itself', r.status === 200 && mine?.keys?.[0]?.key_id === keyId && !JSON.stringify(r.json).includes(secret), mine);

r = await exchange(secret);
check('the key buys a 15-minute token for the agent', r.status === 200 && r.json?.subject === subject && r.json?.expires_in === 900, { status: r.status, subject: r.json?.subject });
const agentToken = r.json?.access_token;
r = await call('GET', '/session/me/', null, { bearer: agentToken });
check('the token is the agent, its own principal', r.status === 200 && JSON.stringify(r.json).includes(subject), r.json);
r = await call('POST', '/todos/', null, { bearer: agentToken, body: { title: 'agent-test todo' } });
check('the agent works todos with its agent role', r.status === 200 || r.status === 201, { status: r.status, body: r.json });
r = await call('GET', '/agents/', null, { bearer: agentToken });
check('the agent cannot manage agents', r.status === 401 || r.status === 403, r.status);
r = await exchange('rk_' + '0'.repeat(48));
check('a wrong key: 401', r.status === 401 && r.json?.error === 'invalid_key', r.json);
r = await exchange(undefined);
check('no key: 400', r.status === 400, r.status);

r = await call('GET', '/agents/', 'OTHER');
check('another person does not see it', r.status === 200 && !r.json?.agents?.some((a) => a.agent_id === agent), r.json?.agents?.length);
r = await call('POST', `/agents/${agent}/keys/`, 'OTHER', { body: { name: 'mine now' }, idem: key('o') });
check('nor makes a key for it: AGENT_NOT_FOUND', r.json?.rejections?.[0]?.rule_id === 'AGENT_NOT_FOUND', r.json);
r = await call('GET', '/agents/?all=true', 'OTHER');
check('nor lists every agent: 403', r.status === 403, r.status);

r = await call('GET', '/agents/?all=true', 'ADMIN');
check('the admin sees every agent, with its owner', r.status === 200 && r.json?.agents?.some((a) => a.agent_id === agent && a.owner), r.status);
r = await call('DELETE', `/agents/${agent}/keys/${keyId}/`, 'ADMIN', { idem: key('rev') });
check('and revokes its key', r.json?.decision === 'accepted', r.json);
r = await exchange(secret);
check('a revoked key buys nothing: 401', r.status === 401, r.status);

r = await call('POST', `/agents/${agent}/keys/`, 'USER1', { body: { name: 'agent-test second' }, idem: key('k2') });
const second = r.json?.result?.api_key;
r = await call('DELETE', `/agents/${agent}/`, 'USER1', { idem: key('ret') });
check('the owner retires the agent', r.json?.decision === 'accepted', r.json);
r = await exchange(second);
check('a retired agent\'s key buys nothing: 401', r.status === 401, r.status);

console.log(`[INFO] agents over HTTP: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
