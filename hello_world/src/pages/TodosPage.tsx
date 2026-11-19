import { FormEvent, useState } from 'react';

import { TodoForm } from '../components/todos/TodoForm';
import { TodoRow } from '../components/todos/TodoRow';
import { useTodos } from '../hooks/useTodos';
import { dateToDueAt } from '../utils/dates';

// Todos (spec-patch-17). The client side of the governed todo surface that agents also use: a
// refusal is an answer shown to the person, a stale token keeps their edit, a create is replayed
// safely. The list, the read token and the actions live in useTodos.

export function TodosPage() {
  const t = useTodos();
  const [search, setSearch] = useState('');

  function handleSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    t.setQuery(search);
  }

  return (
    <div className="stack">
      <div className="section-heading">
        <h2>Todos</h2>
        <p className="muted">
          Your todos. This page uses the same governed API as the agents, so a refusal is shown as the
          database wrote it.
        </p>
      </div>

      {t.notice ? <p className="notice notice--warning" role="status">{t.notice}</p> : null}

      <section className="panel">
        <h3>Add a todo</h3>
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

      <div className="row" role="group" aria-label="Show">
        <button
          aria-pressed={t.status === 'OPEN'}
          className={t.status === 'OPEN' ? 'button' : 'button ghost'}
          onClick={() => t.setTab('OPEN')}
          type="button"
        >Open</button>
        <button
          aria-pressed={t.status === 'DONE'}
          className={t.status === 'DONE' ? 'button' : 'button ghost'}
          onClick={() => t.setTab('DONE')}
          type="button"
        >Done</button>
      </div>

      <form className="row" onSubmit={handleSearch} role="search">
        <label className="field">
          <span>Search titles</span>
          <input onChange={(e) => setSearch(e.target.value)} value={search} />
        </label>
        <button className="button ghost" type="submit">Search</button>
      </form>

      {t.items === null ? <p className="muted">Loading...</p> : null}
      {t.items?.length === 0 ? <p className="muted">No {t.status === 'OPEN' ? 'open' : 'done'} todos.</p> : null}
      {t.items && t.items.length > 0 ? (
        <ul className="stack" style={{ listStyle: 'none', margin: 0, padding: 0 }}>
          {t.items.map((todo) => (
            <TodoRow
              key={todo.todo_id}
              onComplete={t.complete}
              onRemove={t.remove}
              onReopen={t.reopen}
              onRevise={t.revise}
              todo={todo}
            />
          ))}
        </ul>
      ) : null}
      {t.hasMore ? <button className="button ghost" onClick={() => void t.showMore()} type="button">Show more</button> : null}
    </div>
  );
}
