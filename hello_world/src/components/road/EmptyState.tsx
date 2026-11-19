import type { ReactNode } from 'react';

export function EmptyState({ icon, children, action }: { icon?: ReactNode; children: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-10 text-center text-sm text-muted-foreground">
      {icon ? <span aria-hidden="true" className="flex size-10 items-center justify-center rounded-full bg-raised">{icon}</span> : null}
      <p className="m-0 max-w-sm">{children}</p>
      {action}
    </div>
  );
}
