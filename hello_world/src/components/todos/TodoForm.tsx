import { FormEvent, useState } from 'react';

import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import { Textarea } from '../ui/textarea';

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
    <form className="flex flex-col gap-3" onSubmit={(e) => void handleSubmit(e)}>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${idPrefix}-title`}>Title</Label>
        <Input
          id={`${idPrefix}-title`}
          maxLength={200}
          onChange={(e) => setDraft({ ...draft, title: e.target.value })}
          required
          value={draft.title}
        />
      </div>
      <div className="flex flex-wrap gap-3">
        <div className="flex min-w-48 flex-[3_1_16rem] flex-col gap-1.5">
          <Label htmlFor={`${idPrefix}-notes`}>Notes (optional)</Label>
          <Textarea
            id={`${idPrefix}-notes`}
            maxLength={4000}
            onChange={(e) => setDraft({ ...draft, notes: e.target.value })}
            rows={2}
            value={draft.notes}
          />
        </div>
        <div className="flex flex-[1_1_10rem] flex-col gap-1.5">
          <Label htmlFor={`${idPrefix}-due`}>Due date (optional)</Label>
          <Input
            id={`${idPrefix}-due`}
            onChange={(e) => setDraft({ ...draft, date: e.target.value })}
            type="date"
            value={draft.date}
          />
        </div>
      </div>
      <div className="flex gap-2">
        <Button disabled={busy} type="submit">{submitLabel}</Button>
        {onCancel ? <Button onClick={onCancel} type="button" variant="ghost">Cancel</Button> : null}
      </div>
    </form>
  );
}
