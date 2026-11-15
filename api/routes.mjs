// The routes of this application's ORDS modules, from which scripts/generate-modules.mjs writes
// api/modules/<name>/module.create.sql (spec-patch-16). Each route serves one entry of the contract
// (contract/hello_world.gsc.json, with its fragments), and test/contract/check-contract-coverage.mjs
// checks they agree both ways. See the generator's header for the fields.
//
// The modules that are not here are the ones outside the surface: health, auth, ui, api_auth and
// admin (hand-written, listed in the coverage check), contract (public, hand-written) and session
// (a hand-written handler that builds one response from several queries).
export default [
  {
    name: 'todos',
    base: '/api/v1/todos/',
    comment: 'Todo demo: a governed surface (spec-patch-16)',
    routes: [
      { pattern: '/', method: 'GET', id: 'todos.list', kind: 'view',
        call: 'demo_todo_api.list_todos({n:offset}, {n:limit}, :status, :query, {n:owner})' },
      { pattern: '/', method: 'POST', id: 'todos.create', kind: 'action', idempotency: true,
        call: 'demo_todo_api.create_todo(json(:body_text), :idempotency_key)' },
      { pattern: 'purges/', method: 'POST', id: 'todos.purge', kind: 'action', idempotency: true,
        call: 'demo_todo_api.purge_todos(json(:body_text), :idempotency_key)' },
      { pattern: ':id/', method: 'GET', id: 'todos.get', kind: 'view',
        call: 'demo_todo_api.get_todo({n:id})' },
      { pattern: ':id/', method: 'DELETE', id: 'todos.delete', kind: 'action',
        call: 'demo_todo_api.delete_todo({n:id}, json(:body_text))' },
      { pattern: ':id/revisions/', method: 'POST', id: 'todos.revise', kind: 'action',
        call: 'demo_todo_api.revise_todo({n:id}, json(:body_text))' },
      { pattern: ':id/completions/', method: 'POST', id: 'todos.complete', kind: 'action',
        call: 'demo_todo_api.complete_todo({n:id}, json(:body_text))' },
      { pattern: ':id/reopenings/', method: 'POST', id: 'todos.reopen', kind: 'action',
        call: 'demo_todo_api.reopen_todo({n:id}, json(:body_text))' },
    ],
  },
  {
    name: 'agents',
    base: '/api/v1/agents/',
    comment: 'Agents and API keys (spec-patch-15)',
    routes: [
      { pattern: '/', method: 'GET', id: 'agents.list', kind: 'view',
        call: 'road_agent_api.list_agents(:all)' },
      { pattern: '/', method: 'POST', id: 'agents.create', kind: 'action', idempotency: true,
        call: 'road_agent_api.create_agent(json(:body_text), :idempotency_key)' },
      { pattern: ':id/', method: 'DELETE', id: 'agents.retire', kind: 'action', idempotency: true,
        call: 'road_agent_api.retire_agent({n:id}, :idempotency_key)' },
      { pattern: ':id/keys/', method: 'POST', id: 'api_keys.create', kind: 'action', idempotency: true,
        call: 'road_agent_api.create_key({n:id}, json(:body_text), :idempotency_key)' },
      { pattern: ':id/keys/:key_id/', method: 'DELETE', id: 'api_keys.delete', kind: 'action', idempotency: true,
        call: 'road_agent_api.revoke_key({n:id}, {n:key_id}, :idempotency_key)' },
    ],
  },
];
