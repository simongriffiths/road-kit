import { FormEvent, useCallback, useEffect, useState } from 'react';

import { createAgent, createKey, listAgents, newKey, retireAgent, revokeKey } from '../api/agents';
import type { Agent, AgentKey } from '../api/agents';
import { Bot } from 'lucide-react';

import { EmptyState } from '../components/road/EmptyState';
import { Notice } from '../components/road/Notice';
import { PageHeader } from '../components/road/PageHeader';
import { StatusBadge } from '../components/road/StatusBadge';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Skeleton } from '../components/ui/skeleton';
import { pageTitle } from '../config/app';
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

  useEffect(() => { document.title = pageTitle(all ? 'All agents' : 'My agents'); }, [all]);

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
    <>
      <PageHeader
        description="An agent, such as Claude Code, is its own identity that you own. Give it an API key for its command-line tool, one key for each place it runs, so you can revoke one without the others."
        title={all ? 'All agents' : 'My agents'}
      />
      {canSeeAll ? (
        <label className="flex items-center gap-2 text-sm">
          <input checked={all} className="size-4 accent-primary" onChange={(e) => setAll(e.target.checked)} type="checkbox" />
          Show every agent
        </label>
      ) : null}

      {notice ? <Notice kind="warning">{notice}</Notice> : null}

      {made ? (
        <Notice kind="warning" testId="new-key">
          <div className="flex flex-col gap-2">
            <p className="m-0 font-semibold">Key "{made.name}" for {made.agent}: copy it now. It will not be shown again.</p>
            <code className="block rounded-md bg-card p-2 font-mono text-xs text-foreground [overflow-wrap:anywhere]" data-testid="new-key-value">{made.key}</code>
            <div className="flex gap-2">
              <Button onClick={() => void navigator.clipboard.writeText(made.key)} size="sm">Copy key</Button>
              <Button onClick={() => setMade(null)} size="sm" variant="outline">Done</Button>
            </div>
            <p className="m-0">Where the agent runs, run this and paste the key when it asks:</p>
            <code className="block rounded-md bg-card p-2 font-mono text-xs text-foreground [overflow-wrap:anywhere]">road-cli login --url {getOrdsBaseUrl()}</code>
          </div>
        </Notice>
      ) : null}

      {selfServe && !all ? (
        <form className="flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-5" onSubmit={(e) => void handleAgent(e)}>
          <label className="flex min-w-56 flex-1 flex-col gap-1.5 text-sm font-medium">
            New agent
            <Input maxLength={80} onChange={(e) => setName(e.target.value)} placeholder="My Claude Code" required value={name} />
          </label>
          <Button type="submit">Make agent</Button>
        </form>
      ) : null}
      {!selfServe ? <p className="m-0 text-sm text-muted-foreground">Agents are not switched on in this application.</p> : null}

      {agents === null ? <Skeleton className="h-32 w-full rounded-xl" /> : null}
      {agents?.length === 0 ? (
        <div className="rounded-xl border border-border bg-card"><EmptyState icon={<Bot className="size-5" />}>No agents yet.</EmptyState></div>
      ) : null}
      {agents?.map((a) => (
        <section className="flex flex-col gap-4 rounded-xl border border-border bg-card p-5" data-testid={`agent-${a.agent_id}`} key={a.agent_id}>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <h2 className="m-0 text-base font-semibold [overflow-wrap:anywhere]">{a.display_name}</h2>
            <StatusBadge kind={a.status === 'ACTIVE' ? 'success' : 'neutral'}>{a.status.toLowerCase()}</StatusBadge>
            <span className="min-w-0 flex-1 text-xs text-muted-foreground [overflow-wrap:anywhere]">{a.subject}{a.owner ? `, owned by ${a.owner}` : ', shared'}</span>
            {a.status === 'ACTIVE' ? <Button onClick={() => handleRetire(a)} size="sm" variant="outline">Retire</Button> : null}
          </div>
          {(a.keys ?? []).length > 0 ? (
            <ul className="m-0 list-none overflow-hidden rounded-lg border border-divider p-0">
              {(a.keys ?? []).map((k) => (
                <li className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-divider px-3.5 py-2.5 text-sm last:border-b-0" key={k.key_id}>
                  <span className="min-w-0 flex-1 basis-40 font-medium [overflow-wrap:anywhere]">{k.name}</span>
                  <code className="font-mono text-xs">{k.key_prefix}...</code>
                  <span className="text-xs text-muted-foreground">last used {when(k.last_used_at)}</span>
                  {k.revoked_at
                    ? <StatusBadge>revoked</StatusBadge>
                    : <Button onClick={() => handleRevoke(a, k)} size="sm" variant="ghost">Revoke</Button>}
                </li>
              ))}
            </ul>
          ) : null}
          {a.status === 'ACTIVE' ? (
            <form className="flex flex-wrap items-end gap-3" onSubmit={(e) => void handleKey(e, a)}>
              <label className="flex min-w-56 flex-1 flex-col gap-1.5 text-sm font-medium">
                Where the key will be used
                <Input
                  aria-label={`Key name for ${a.display_name}`}
                  maxLength={80}
                  onChange={(e) => setKeyNames({ ...keyNames, [a.agent_id]: e.target.value })}
                  placeholder="the MacBook"
                  required
                  value={keyNames[a.agent_id] ?? ''}
                />
              </label>
              <Button type="submit">Make a key</Button>
            </form>
          ) : null}
        </section>
      ))}
    </>
  );
}
