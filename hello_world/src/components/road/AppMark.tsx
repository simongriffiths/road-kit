import { Check } from 'lucide-react';

import { app } from '../../config/app';

// The mark beside the app name: a tick on a rounded square in the primary colour. An app replaces
// this file to change its mark (spec-patch-18 section 5). The name takes the colour around it;
// `inverted` is for use on a primary-coloured panel.
export function AppMark({ showName = true, inverted = false }: { showName?: boolean; inverted?: boolean }) {
  return (
    <span className="flex items-center gap-2.5">
      <span
        aria-hidden="true"
        className={`flex size-[30px] items-center justify-center rounded-lg ${inverted ? 'bg-primary-foreground text-primary-strong' : 'bg-primary text-primary-foreground'}`}
      >
        <Check className="size-[18px]" strokeWidth={2.6} />
      </span>
      {showName ? <span className="text-[17px] font-bold tracking-tight">{app.name}</span> : null}
    </span>
  );
}
