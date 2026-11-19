import { FormEvent, useEffect, useMemo, useState } from 'react';
import { ListChecks, Search } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';

import type { Todo } from '../api/todos';
import { DataList } from '../components/road/DataList';
import type { DataGroup } from '../components/road/DataList';
import { EmptyState } from '../components/road/EmptyState';
import { Notice } from '../components/road/Notice';
import { PageHeader } from '../components/road/PageHeader';
import { SegmentedControl } from '../components/road/SegmentedControl';
import { TodoForm } from '../components/todos/TodoForm';
import { TodoRow } from '../components/todos/TodoRow';
import { Button } from '../components/ui/button';
import { Skeleton } from '../components/ui/skeleton';
import { pageTitle } from '../config/app';
import { useTodos } from '../hooks/useTodos';
import { dateToDueAt, dueBucket } from '../utils/dates';
import type { DueBucket } from '../utils/dates';

// Todos (spec-patch-17, restyled by spec-patch-18 section 7.3). The client side of the governed todo
// surface that agents also use: a refusal is an answer shown to the person, a stale token keeps
// their edit, a create is replayed safely. The list, the read token and the actions live in useTodos.

const GROUPS: { bucket: DueBucket; label: string }[] = [
  { bucket: 'overdue', label: 'Overdue' },
  { bucket: 'today', label: 'Today' },
  { bucket: 'later', label: 'Later' },
  { bucket: 'none', label: 'No date' }
];

export function TodosPage() {
  const t = useTodos();
  const [params] = useSearchParams();
  const fromUrl = params.get('q') ?? '';
  const [search, setSearch] = useState(fromUrl);

  useEffect(() => { document.title = pageTitle('Todos'); }, []);
  useEffect(() => {
    setSearch(fromUrl);
    t.setQuery(fromUrl);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fromUrl]);

  function handleSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    t.setQuery(search);
  }

  const row = (todo: Todo) => (
    <TodoRow key={todo.todo_id} onComplete={t.complete} onRemove={t.remove} onReopen={t.reopen} onRevise={t.revise} todo={todo} />
  );

  const groups: DataGroup[] = useMemo(() => {
    if (!t.items) return [];
    if (t.status === 'DONE') return [{ rows: t.items.map(row) }];
    return GROUPS
      .map((g) => ({ label: g.label, rows: t.items!.filter((x) => dueBucket(x.due_at) === g.bucket).map(row) }))
      .filter((g) => g.rows.length > 0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [t.items, t.status]);

  return (
    <>
      <PageHeader
        description="Your todos. This page uses the same governed API as the agents, so a refusal is shown as the database wrote it."
        title="Todos"
      />

      {t.notice ? <Notice kind="warning">{t.notice}</Notice> : null}

      <section aria-labelledby="add-heading" className="flex flex-col gap-3 rounded-xl border border-border bg-card p-5">
        <h2 className="m-0 text-base font-semibold" id="add-heading">Add a todo</h2>
        <TodoForm
          clearOnAccept
          idPrefix="add"
          initial={{ title: '', notes: '', date: '' }}
          onSubmit={async (d) => {
            const s = await t.add({
              title: d.title,
              ...(d.notes ? { notes: d.notes } : {}),
              ...(d.date ? { due_at: dateToDueAt(d.date) } : {})
            });
            return s.accepted;
          }}
          submitLabel="Add todo"
        />
      </section>

      <div className="flex flex-wrap items-center gap-3">
        <SegmentedControl
          label="Show"
          onChange={t.setTab}
          options={[{ value: 'OPEN', label: 'Open' }, { value: 'DONE', label: 'Done' }]}
          value={t.status}
        />
        <form className="ml-auto flex min-w-60 flex-1 basis-60 items-center gap-2 sm:flex-none sm:basis-80" aria-label="Search this list" onSubmit={handleSearch} role="search">
          <label className="sr-only" htmlFor="todo-search">Search titles</label>
          <div className="relative flex-1">
            <Search aria-hidden="true" className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
            <input
              className="h-9 w-full rounded-lg border border-input bg-card pl-8 pr-3 text-sm outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
              id="todo-search"
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search titles"
              type="search"
              value={search}
            />
          </div>
          <Button type="submit" variant="outline">Search</Button>
        </form>
      </div>

      {t.items === null ? <Skeleton className="h-48 w-full rounded-xl" /> : null}
      {t.items?.length === 0 ? (
        <div className="rounded-xl border border-border bg-card">
          <EmptyState icon={<ListChecks className="size-5" />}>
            {t.query ? `No ${t.status === 'OPEN' ? 'open' : 'done'} todos match "${t.query}".` : `No ${t.status === 'OPEN' ? 'open' : 'done'} todos.`}
          </EmptyState>
        </div>
      ) : null}
      {t.items && t.items.length > 0 ? <DataList groups={groups} label={t.status === 'OPEN' ? 'Open todos' : 'Done todos'} /> : null}
      {t.hasMore ? <Button className="self-start" onClick={() => void t.showMore()} variant="outline">Show more</Button> : null}
    </>
  );
}
