import { useState } from 'react';

import type { Todo, TodoFields } from '../../api/todos';
import type { Settled } from '../../hooks/useTodos';
import { dateToDueAt, dueAtToDate, showDate } from '../../utils/dates';
import { TodoForm } from './TodoForm';
import type { TodoDraft } from './TodoForm';

// One todo: its title, first line of notes, due date and buttons, or its edit form (spec-patch-17 3.1,
// 3.3, 3.4). The form stays open after a stale-token answer, with the person's text in it.

interface TodoRowProps {
  todo: Todo;
  onComplete: (id: number) => Promise<Settled>;
  onReopen: (id: number) => Promise<Settled>;
  onRemove: (id: number) => Promise<Settled>;
  onRevise: (id: number, changes: Partial<TodoFields>) => Promise<Settled>;
}

export function TodoRow({ todo, onComplete, onReopen, onRemove, onRevise }: TodoRowProps) {
  const [editing, setEditing] = useState(false);
  const done = todo.status === 'DONE';

  async function save(draft: TodoDraft) {
    const changes: Partial<TodoFields> = {};
    if (draft.title !== todo.title) changes.title = draft.title;
    if (draft.notes !== (todo.notes ?? '')) changes.notes = draft.notes === '' ? null : draft.notes;
    if (draft.date !== dueAtToDate(todo.due_at)) changes.due_at = draft.date === '' ? null : dateToDueAt(draft.date);
    if (Object.keys(changes).length === 0) {
      setEditing(false);
      return true;
    }
    const s = await onRevise(todo.todo_id, changes);
    if (s.accepted) setEditing(false);
    return s.accepted;
  }

  function handleDelete() {
    if (window.confirm(`Delete "${todo.title}"?`)) void onRemove(todo.todo_id);
  }

  if (editing) {
    return (
      <li className="panel" data-testid={`todo-${todo.todo_id}`}>
        <TodoForm
          idPrefix={`edit-${todo.todo_id}`}
          initial={{ title: todo.title, notes: todo.notes ?? '', date: dueAtToDate(todo.due_at) }}
          onCancel={() => setEditing(false)}
          onSubmit={save}
          submitLabel="Save"
        />
      </li>
    );
  }

  const firstLine = todo.notes ? todo.notes.split('\n')[0] : '';

  return (
    <li className="panel" data-testid={`todo-${todo.todo_id}`}>
      <div className="stack">
        <div>
          <strong>{todo.title}</strong>
          {firstLine ? <p className="muted">{firstLine}</p> : null}
          {todo.due_at ? <p className="muted">Due {showDate(todo.due_at)}</p> : null}
        </div>
        <div className="row">
          {done
            ? <button className="button" onClick={() => void onReopen(todo.todo_id)} type="button">Reopen</button>
            : <button className="button" onClick={() => void onComplete(todo.todo_id)} type="button">Done</button>}
          <button className="button ghost" onClick={() => setEditing(true)} type="button">Edit</button>
          <button className="button ghost" onClick={handleDelete} type="button">Delete</button>
        </div>
      </div>
    </li>
  );
}
