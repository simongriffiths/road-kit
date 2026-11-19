import type { RefObject } from 'react';
import { Button } from '../ui/button';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '../ui/sheet';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../ui/tabs';
import { Notice } from './Notice';
import { ValueList, copyText, sessionSections } from './SessionSections';
import type { useSession } from '../../hooks/useSession';

export type DrawerTab = 'session' | 'connection' | 'contract';

// What the database knows about this sign-in, in a side panel (spec-patch-18 section 6.1). It opens
// from the account menu. Closing it returns focus to the account button.
export function SessionDrawer({ tab, onTabChange, onClose, state, returnFocusTo }: {
  tab: DrawerTab | null;
  onTabChange: (t: DrawerTab) => void;
  onClose: () => void;
  state: ReturnType<typeof useSession>;
  returnFocusTo: RefObject<HTMLElement | null>;
}) {
  const sections = sessionSections(state.session);
  const json = JSON.stringify(
    Object.fromEntries(sections.map((s) => [s.id, Object.fromEntries(s.rows.map((r) => [r.k, r.v]))])),
    null,
    2
  );

  return (
    <Sheet onOpenChange={(open) => { if (!open) onClose(); }} open={tab !== null}>
      <SheetContent className="w-full gap-0 sm:max-w-[520px]" finalFocus={returnFocusTo}>
        <SheetHeader className="border-b border-divider p-5 pr-14">
          <SheetTitle className="text-lg font-semibold">Session details</SheetTitle>
          <SheetDescription>What the database knows about this sign-in, read from /session/me/.</SheetDescription>
        </SheetHeader>

        <Tabs className="min-h-0 flex-1 gap-0" onValueChange={(v) => onTabChange(v as DrawerTab)} value={tab ?? 'session'}>
          <TabsList className="mx-5 mt-3">
            {sections.map((s) => <TabsTrigger className="text-ink-soft data-active:text-foreground" key={s.id} value={s.id}>{s.label}</TabsTrigger>)}
          </TabsList>
          <div className="flex-1 overflow-y-auto p-5">
            {state.error ? <Notice kind="error">{state.error}</Notice> : null}
            {sections.map((s) => (
              <TabsContent className="flex flex-col gap-4" key={s.id} value={s.id}>
                {s.id === 'session' && state.session ? (
                  <Notice kind="info">Token accepted. ORDS checked it and PL/SQL mapped it to a database session.</Notice>
                ) : null}
                <ValueList rows={s.rows} />
              </TabsContent>
            ))}
          </div>
        </Tabs>

        <div className="flex flex-wrap items-center gap-2 border-t border-divider bg-raised px-5 py-3">
          <Button onClick={() => void copyText(json, 'all details as JSON')} variant="outline">Copy all as JSON</Button>
          <Button disabled={state.loading} onClick={() => void state.read()} variant="outline">Read again</Button>
          <span className="ml-auto text-xs text-muted-foreground">
            {state.readAt ? `Read at ${state.readAt.toLocaleTimeString()}` : 'Reading…'}
          </span>
        </div>
      </SheetContent>
    </Sheet>
  );
}
