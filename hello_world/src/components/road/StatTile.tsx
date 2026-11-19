// A label, a figure and one line of note. `tone` colours the figure; the note must say in words
// what a warning or error tone means.
export function StatTile({ label, value, note, tone = 'neutral' }: {
  label: string;
  value: string;
  note?: string;
  tone?: 'neutral' | 'error';
}) {
  return (
    <div className="flex flex-col gap-1.5 rounded-xl border border-border bg-card px-5 py-4">
      <span className="text-[13px] text-muted-foreground">{label}</span>
      <span className={`text-3xl font-semibold tracking-tight ${tone === 'error' ? 'text-error-fg' : ''}`}>{value}</span>
      {note ? <span className="text-xs text-muted-foreground">{note}</span> : null}
    </div>
  );
}
