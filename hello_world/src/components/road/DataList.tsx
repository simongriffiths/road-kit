import type { ReactNode } from 'react';

export interface DataGroup {
  label?: string;
  count?: number;
  rows: ReactNode[];
}

// A list of rows, optionally in groups with a header each. Each row is a <li> made with DataRow, or
// by the caller. Below 640 px a row's actions wrap under its text, so the page never scrolls sideways.
export function DataList({ groups, label }: { groups: DataGroup[]; label: string }) {
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-card">
      {groups.map((g, i) => (
        <section aria-label={g.label ? `${g.label}, ${g.rows.length}` : label} key={g.label ?? i}>
          {g.label ? (
            <div className="flex items-center gap-2 border-b border-divider bg-raised px-5 py-2.5 text-xs font-semibold text-ink-soft">
              <h2 className="m-0 flex-1 text-xs font-semibold">{g.label}</h2>
              <span className="font-medium text-muted-foreground">{g.count ?? g.rows.length}</span>
            </div>
          ) : null}
          <ul className="m-0 list-none p-0">{g.rows}</ul>
        </section>
      ))}
    </div>
  );
}

export function DataRow({ testId, leading, title, secondary, badge, actions }: {
  testId?: string;
  leading?: ReactNode;
  title: ReactNode;
  secondary?: ReactNode;
  badge?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <li className="flex flex-wrap items-center gap-x-3.5 gap-y-2 border-b border-divider px-5 py-3 last:border-b-0" data-testid={testId}>
      {leading}
      <div className="flex min-w-0 flex-1 basis-56 flex-col gap-0.5">
        <span className="text-sm font-medium [overflow-wrap:anywhere]">{title}</span>
        {secondary ? <span className="text-xs text-muted-foreground [overflow-wrap:anywhere]">{secondary}</span> : null}
      </div>
      {badge}
      {actions ? <div className="flex flex-wrap items-center gap-1.5">{actions}</div> : null}
    </li>
  );
}
