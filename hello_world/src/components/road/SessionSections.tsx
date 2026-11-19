import { Copy } from 'lucide-react';
import { toast } from 'sonner';

import { API_VERSION, APP_NAME, UI_BASE_PATH, getOrdsBaseUrl } from '../../config/runtime';
import type { SessionIdentity } from '../../types/api';
import { Button } from '../ui/button';

// The three groups of facts about this sign-in, shared by the session drawer and the /session page
// (spec-patch-18 section 6.1). The auth profile is not shown: it is a server setting the browser
// build does not receive.

export type Row = { k: string; v: string };
export type Section = { id: 'session' | 'connection' | 'contract'; label: string; rows: Row[] };

export function sessionSections(s: SessionIdentity | null): Section[] {
  const none = '…';
  return [
    {
      id: 'session',
      label: 'Session',
      rows: [
        { k: 'Principal', v: s?.principal ?? none },
        { k: 'Current user', v: s?.current_user ?? none },
        { k: 'Database user', v: s?.db_user ?? none },
        { k: 'Issuer', v: s?.issuer ?? none },
        { k: 'Audience', v: s?.audience ?? none },
        { k: 'Scope', v: s?.scope ?? none },
        { k: 'Authenticated', v: s?.authenticated ?? none }
      ]
    },
    {
      id: 'connection',
      label: 'Connection',
      rows: [
        { k: 'App name', v: APP_NAME },
        { k: 'UI base path', v: UI_BASE_PATH },
        { k: 'API base URL', v: getOrdsBaseUrl() }
      ]
    },
    {
      id: 'contract',
      label: 'Contract',
      rows: [
        { k: 'Accept-Version sent', v: API_VERSION },
        { k: 'Contract version', v: s?.contract_version ?? 'not reported' }
      ]
    }
  ];
}

export async function copyText(text: string, what: string) {
  try {
    await navigator.clipboard.writeText(text);
    toast.success(`Copied ${what}.`);
  } catch {
    toast.error('Could not copy. Select the text and copy it yourself.');
  }
}

export function ValueList({ rows }: { rows: Row[] }) {
  return (
    <dl className="m-0 overflow-hidden rounded-lg border border-divider">
      {rows.map((r) => (
        <div className="flex items-center gap-3 border-b border-divider px-3.5 py-2 last:border-b-0" key={r.k}>
          <dt className="w-32 shrink-0 text-[13px] text-muted-foreground">{r.k}</dt>
          <dd className="m-0 flex min-w-0 flex-1 items-center gap-2">
            <span className="min-w-0 flex-1 font-mono text-[12.5px] [overflow-wrap:anywhere]">{r.v}</span>
            <Button aria-label={`Copy ${r.k}`} onClick={() => void copyText(r.v, r.k)} size="icon-sm" variant="ghost">
              <Copy />
            </Button>
          </dd>
        </div>
      ))}
    </dl>
  );
}
