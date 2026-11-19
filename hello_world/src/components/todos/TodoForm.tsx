import { FormEvent, useState } from 'react';

// The fields of a todo, shared by the add form and the row's edit form (spec-patch-17 3.2, 3.3).
// It keeps what the person typed until the owner of the form says it was accepted, so a refusal or
// a stale token never loses their text.

export interface TodoDraft {
  title: string;
  notes: string;
  date: string;
}

interface TodoFormProps {
  idPrefix: string;
  initial: TodoDraft;
  submitLabel: string;
  // Resolves true when the change was accepted.
  onSubmit: (draft: TodoDraft) => Promise<boolean>;
  onCancel?: () => void;
  clearOnAccept?: boolean;
}

export function TodoForm({ idPrefix, initial, submitLabel, onSubmit, onCancel, clearOnAccept }: TodoFormProps) {
  const [draft, setDraft] = useState<TodoDraft>(initial);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const accepted = await onSubmit({ ...draft, title: draft.title.trim() });
    setBusy(false);
    if (accepted && clearOnAccept) setDraft(initial);
  }

  return (
    <form className="stack" onSubmit={(e) => void handleSubmit(e)}>
      <label className="field" htmlFor={`${idPrefix}-title`}>
        <span>Title</span>
        <input
          id={`${idPrefix}-title`}
          maxLength={200}
          onChange={(e) => setDraft({ ...draft, title: e.target.value })}
          required
          value={draft.title}
        />
      </label>
      <label className="field" htmlFor={`${idPrefix}-notes`}>
        <span>Notes (optional)</span>
        <textarea
          id={`${idPrefix}-notes`}
          maxLength={4000}
          onChange={(e) => setDraft({ ...draft, notes: e.target.value })}
          rows={2}
          value={draft.notes}
        />
      </label>
      <label className="field" htmlFor={`${idPrefix}-due`}>
        <span>Due date (optional)</span>
        <input
          id={`${idPrefix}-due`}
          onChange={(e) => setDraft({ ...draft, date: e.target.value })}
          type="date"
          value={draft.date}
        />
      </label>
      <div className="row">
        <button className="button" disabled={busy} type="submit">{submitLabel}</button>
        {onCancel ? <button className="button ghost" onClick={onCancel} type="button">Cancel</button> : null}
      </div>
    </form>
  );
}
