import type { ReactNode } from 'react';

// Title, one line of description, an optional line above (a date) and optional actions.
export function PageHeader({ title, description, eyebrow, actions }: {
  title: string;
  description?: ReactNode;
  eyebrow?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end gap-4">
      <div className="min-w-0 flex-1 basis-80">
        {eyebrow ? <span className="text-[13px] text-eyebrow">{eyebrow}</span> : null}
        <h1 className="m-0 text-balance text-[1.7rem] font-semibold tracking-tight">{title}</h1>
        {description ? <p className="mt-1.5 text-[15px] text-muted-foreground">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
