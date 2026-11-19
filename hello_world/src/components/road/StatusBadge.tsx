import type { ReactNode } from 'react';

type Kind = 'success' | 'info' | 'warning' | 'error' | 'neutral';

const styles: Record<Kind, string> = {
  success: 'bg-success-bg text-success-fg border-success-border',
  info: 'bg-info-bg text-info-fg border-info-border',
  warning: 'bg-warning-bg text-warning-fg border-warning-border',
  error: 'bg-error-bg text-error-fg border-error-border',
  neutral: 'bg-card text-ink-soft border-border'
};

// A word on a tinted pill. The word carries the meaning; the colour only supports it.
export function StatusBadge({ kind = 'neutral', children }: { kind?: Kind; children: ReactNode }) {
  return (
    <span className={`inline-flex items-center whitespace-nowrap rounded-full border px-2.5 py-0.5 text-xs font-medium ${styles[kind]}`}>
      {children}
    </span>
  );
}
