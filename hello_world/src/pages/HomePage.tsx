import { useEffect } from 'react';
import { Bot, CircleCheck, Plus } from 'lucide-react';
import { Link } from 'react-router-dom';

import { DataList, DataRow } from '../components/road/DataList';
import { EmptyState } from '../components/road/EmptyState';
import { Notice } from '../components/road/Notice';
import { PageHeader } from '../components/road/PageHeader';
import { StatTile } from '../components/road/StatTile';
import { StatusBadge } from '../components/road/StatusBadge';
import { Button, buttonVariants } from '../components/ui/button';
import { Skeleton } from '../components/ui/skeleton';
import { pageTitle } from '../config/app';
import { HOME_LIMIT, useHomeSummary } from '../hooks/useHomeSummary';
import { dueBucket, showShortDate } from '../utils/dates';

// Home (spec-patch-18 section 7.2): what needs doing today, and the agents. Counts come from one
// read of up to 100 open todos, and the page says so when there are more.

function greeting(now = new Date()): string {
  const h = now.getHours();
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
}

export function HomePage() {
  const h = useHomeSummary();
  useEffect(() => { document.title = pageTitle(); }, []);

  const c = h.counts;
  const capped = h.more ? `Of your latest ${HOME_LIMIT} open todos` : undefined;
  const summary = h.todos === null
    ? 'Reading your todos…'
    : c.today + c.overdue === 0
      ? 'Nothing is due today.'
      : `${c.today} ${c.today === 1 ? 'todo is' : 'todos are'} due today and ${c.overdue} ${c.overdue === 1 ? 'is' : 'are'} overdue.`;

  return (
    <>
      <PageHeader
        actions={<Link className={buttonVariants({ size: 'lg', className: 'no-underline' })} to="/todos"><Plus /> Add todo</Link>}
        description={summary}
        eyebrow={new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}
        title={greeting()}
      />

      {h.notice ? <Notice kind="warning">{h.notice}</Notice> : null}

      <div className="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))' }}>
        <StatTile label="Open" note={capped ?? 'Across all your todos'} value={h.more ? `${HOME_LIMIT}+` : String(c.open)} />
        <StatTile label="Due today" note={capped ?? 'Open todos due today'} value={String(c.today)} />
        <StatTile label="Overdue" note={c.overdue > 0 ? 'Overdue: past their due date' : (capped ?? 'None past their due date')} tone={c.overdue > 0 ? 'error' : 'neutral'} value={String(c.overdue)} />
      </div>

      <div className="flex flex-wrap items-start gap-5">
        <section className="min-w-0 flex-[999_1_28rem]">
          <div className="mb-3 flex items-center gap-3">
            <h2 className="m-0 flex-1 text-base font-semibold">Due today</h2>
            <Link className="text-[13px] font-medium" to="/todos">All todos</Link>
          </div>
          {h.todos === null ? <Skeleton className="h-40 w-full rounded-xl" /> : null}
          {h.todos && h.dueList.length === 0 ? (
            <div className="rounded-xl border border-border bg-card">
              <EmptyState icon={<CircleCheck className="size-5" />}>Nothing is due today or overdue.</EmptyState>
            </div>
          ) : null}
          {h.dueList.length > 0 ? (
            <DataList
              groups={[{
                rows: h.dueList.map((t) => (
                  <DataRow
                    actions={<Button onClick={() => void h.complete(t.todo_id)} size="sm" variant="outline">Done</Button>}
                    badge={dueBucket(t.due_at) === 'overdue'
                      ? <StatusBadge kind="error">Overdue · {showShortDate(t.due_at!)}</StatusBadge>
                      : <StatusBadge kind="info">Today</StatusBadge>}
                    key={t.todo_id}
                    secondary={t.notes ? t.notes.split('\n')[0] : undefined}
                    title={t.title}
                  />
                ))
              }]}
              label="Due today"
            />
          ) : null}
        </section>

        <section className="flex min-w-0 flex-[1_1_18rem] flex-col gap-3 rounded-xl border border-border bg-card p-5">
          <div className="flex items-center gap-2">
            <h2 className="m-0 flex-1 text-base font-semibold">Agents</h2>
            {h.agents ? <span className="text-xs text-muted-foreground">{h.agents.length} active</span> : null}
          </div>
          {h.agents === null ? <Skeleton className="h-16 w-full" /> : null}
          {h.agents && h.agents.length === 0 ? (
            <EmptyState action={<Link className={buttonVariants({ variant: 'outline', className: 'no-underline' })} to="/agents">Make an agent</Link>} icon={<Bot className="size-5" />}>
              No agents yet. An agent can use your todos through its own API key.
            </EmptyState>
          ) : null}
          {h.agents?.map((a) => {
            const used = (a.keys ?? []).map((k) => k.last_used_at).filter(Boolean).sort().pop();
            return (
              <div className="flex items-start gap-3" key={a.agent_id}>
                <span aria-hidden="true" className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-secondary"><Bot className="size-4" /></span>
                <span className="flex min-w-0 flex-col">
                  <span className="text-sm font-medium [overflow-wrap:anywhere]">{a.display_name}</span>
                  <span className="text-xs text-muted-foreground">{used ? `Key last used ${new Date(used).toLocaleString()}` : 'Not used yet'}</span>
                </span>
              </div>
            );
          })}
          {h.agents && h.agents.length > 0 ? <Link className="text-[13px] font-medium" to="/agents">Manage agents</Link> : null}
        </section>
      </div>
    </>
  );
}
