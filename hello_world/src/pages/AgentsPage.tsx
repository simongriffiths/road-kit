import { FormEvent, useCallback, useEffect, useState } from 'react';

import { createAgent, createKey, listAgents, newKey, retireAgent, revokeKey } from '../api/agents';
import type { Agent, AgentKey } from '../api/agents';
import { getOrdsBaseUrl } from '../config/runtime';
import { isApiError } from '../types/api';
import type { GovernedOutcome } from '../types/api';

// My agents (spec-patch-15 section 4.6). A person makes agents of their own, each its own identity
// that they own, and keys for them; a key is shown once and never again. Holders of
// road.api_key.manage switch to All agents, to see and revoke everyone's.

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString() : 'never');
const refusal = (o: GovernedOutcome) => (o.decision === 'rejected' ? o.rejections.map((r) => r.message).join(' ') : null);

export function AgentsPage() {
  const [agents, setAgents] = useState<Agent[] | null>(null);
  const [all, setAll] = useState(false);
  const [canSeeAll, setCanSeeAll] = useState(false);
  const [selfServe, setSelfServe] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [agentKey, setAgentKey] = useState(newKey());
  const [keyNames, setKeyNames] = useState<Record<number, string>>({});
  const [made, setMade] = useState<{ agent: string; name: string; key: string } | null>(null);

  const load = useCallback(async () => {
    try {
      const r = await listAgents(all);
      setAgents(r.agents);
      setSelfServe(r.self_serve);
    } catch (e) {
      setNotice(isApiError(e) && e.status === 403 ? 'You may not manage agents here.' : 'Could not load your agents.');
      setAgents([]);
    }
  }, [all]);

  useEffect(() => {
    void load();
    void listAgents(true).then(() => setCanSeeAll(true)).catch(() => setCanSeeAll(false));
  }, [load]);

  async function act(work: () => Promise<GovernedOutcome>, done?: string) {
    try {
      const o = await work();
      setNotice(refusal(o) ?? done ?? null);
      await load();
      return o;
    } catch (e) {
      setNotice(isApiError(e) ? e.message : 'Something went wrong.');
      return null;
    }
  }

  async function handleAgent(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const o = await act(() => createAgent(name.trim(), agentKey), `Made ${name.trim()}.`);
    if (o?.decision === 'accepted') {
      setName('');
      setAgentKey(newKey());
    }
  }

  async function handleKey(event: FormEvent<HTMLFormElement>, agent: Agent) {
    event.preventDefault();
    const keyName = (keyNames[agent.agent_id] ?? '').trim();
    const o = await act(() => createKey(agent.agent_id, keyName));
    if (o?.decision === 'accepted') {
      const secret = (o.result as { api_key?: string }).api_key;
      setMade(secret ? { agent: agent.display_name, name: keyName, key: secret } : null);
      setKeyNames({ ...keyNames, [agent.agent_id]: '' });
    }
  }

  function handleRevoke(agent: Agent, k: AgentKey) {
    if (window.confirm(`Revoke "${k.name}" (${k.key_prefix}...)? Tools using it stop within 15 minutes.`)) {
      void act(() => revokeKey(agent.agent_id, k.key_id), `Revoked "${k.name}".`);
    }
  }

  function handleRetire(agent: Agent) {
    if (window.confirm(`Retire ${agent.display_name}? Its keys stop working and it cannot be used again.`)) {
      void act(() => retireAgent(agent.agent_id), `Retired ${agent.display_name}.`);
    }
  }

  return (
    <div className="stack">
      <div className="section-heading">
        <h2>{all ? 'All agents' : 'My agents'}</h2>
        <p className="muted">
          An agent, such as Claude Code, is its own identity that you own. Give it an API key for its command-line tool,
          one key for each place it runs, so you can revoke one without the others.
        </p>
        {canSeeAll ? (
          <label className="row">
            <input checked={all} onChange={(e) => setAll(e.target.checked)} type="checkbox" />
            Show every agent
          </label>
        ) : null}
      </div>

      {notice ? <p className="notice notice--warning" role="status">{notice}</p> : null}

      {made ? (
        <section className="notice notice--warning" data-testid="new-key">
          <p><strong>Key "{made.name}" for {made.agent}: copy it now. It will not be shown again.</strong></p>
          <p><code data-testid="new-key-value">{made.key}</code></p>
          <p className="row">
            <button className="button" onClick={() => void navigator.clipboard.writeText(made.key)} type="button">Copy key</button>
            <button className="button ghost" onClick={() => setMade(null)} type="button">Done</button>
          </p>
          <p className="muted">Where the agent runs, run this and paste the key when it asks:</p>
          <p><code>road-cli login --url {getOrdsBaseUrl()}</code></p>
        </section>
      ) : null}

      {selfServe && !all ? (
        <form className="row" onSubmit={(e) => void handleAgent(e)}>
          <label className="field">
            <span>New agent</span>
            <input maxLength={80} onChange={(e) => setName(e.target.value)} placeholder="My Claude Code" required value={name} />
          </label>
          <button className="button" type="submit">Make agent</button>
        </form>
      ) : null}
      {!selfServe ? <p className="muted">Agents are not switched on in this application.</p> : null}

      {agents === null ? <p className="muted">Loading...</p> : null}
      {agents?.length === 0 ? <p className="muted">No agents yet.</p> : null}
      {agents?.map((a) => (
        <section className="panel" data-testid={`agent-${a.agent_id}`} key={a.agent_id}>
          <div className="row">
            <h3>{a.display_name}</h3>
            <span className="muted">{a.subject}{a.owner ? `, owned by ${a.owner}` : ', shared'} · {a.status.toLowerCase()}</span>
            {a.status === 'ACTIVE' ? (
              <button className="button ghost" onClick={() => handleRetire(a)} type="button">Retire</button>
            ) : null}
          </div>
          <table>
            <tbody>
              {(a.keys ?? []).map((k) => (
                <tr key={k.key_id}>
                  <td>{k.name}</td>
                  <td><code>{k.key_prefix}...</code></td>
                  <td className="muted">last used {when(k.last_used_at)}</td>
                  <td>
                    {k.revoked_at
                      ? <span className="muted">revoked</span>
                      : <button className="button ghost" onClick={() => handleRevoke(a, k)} type="button">Revoke</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {a.status === 'ACTIVE' ? (
            <form className="row" onSubmit={(e) => void handleKey(e, a)}>
              <label className="field">
                <span>Where the key will be used</span>
                <input
                  aria-label={`Key name for ${a.display_name}`}
                  maxLength={80}
                  onChange={(e) => setKeyNames({ ...keyNames, [a.agent_id]: e.target.value })}
                  placeholder="the MacBook"
                  required
                  value={keyNames[a.agent_id] ?? ''}
                />
              </label>
              <button className="button" type="submit">Make a key</button>
            </form>
          ) : null}
        </section>
      ))}
    </div>
  );
}
