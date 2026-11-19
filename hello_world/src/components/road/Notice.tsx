import type { ReactNode } from 'react';
import { CircleAlert, Info, TriangleAlert } from 'lucide-react';

type Kind = 'info' | 'warning' | 'error';

const styles: Record<Kind, string> = {
  info: 'bg-info-bg text-info-fg border-info-border',
  warning: 'bg-warning-bg text-warning-fg border-warning-border',
  error: 'bg-error-bg text-error-fg border-error-border'
};
const icons = { info: Info, warning: TriangleAlert, error: CircleAlert };

// Information, a warning or an error, with an optional action. Errors are announced at once
// (role alert); the others politely (role status).
export function Notice({ kind = 'info', children, action, testId }: {
  kind?: Kind;
  children: ReactNode;
  action?: ReactNode;
  testId?: string;
}) {
  const Icon = icons[kind];
  return (
    <div
      className={`flex items-start gap-2.5 rounded-lg border px-3.5 py-3 text-[13px] ${styles[kind]}`}
      data-testid={testId}
      role={kind === 'error' ? 'alert' : 'status'}
    >
      <Icon aria-hidden="true" className="mt-px size-4 shrink-0" />
      <div className="min-w-0 flex-1">{children}</div>
      {action}
    </div>
  );
}
