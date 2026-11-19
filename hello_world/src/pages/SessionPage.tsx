import { useEffect } from 'react';

import { Notice } from '../components/road/Notice';
import { PageHeader } from '../components/road/PageHeader';
import { ValueList, sessionSections } from '../components/road/SessionSections';
import { Button } from '../components/ui/button';
import { pageTitle } from '../config/app';
import { useSession } from '../hooks/useSession';

// The same facts as the session drawer, as a page, for direct links and tests (spec-patch-18 6.1).
export function SessionPage() {
  const state = useSession(true);
  useEffect(() => { document.title = pageTitle('Session'); }, []);

  return (
    <>
      <PageHeader
        actions={<Button disabled={state.loading} onClick={() => void state.read()} variant="outline">Read again</Button>}
        description="This page shows that the browser token, ORDS privilege enforcement and the PL/SQL session mapping agree."
        title="Session details"
      />
      {state.error ? <Notice kind="error">{state.error}</Notice> : null}
      {sessionSections(state.session).map((s) => (
        <section className="flex flex-col gap-2" key={s.id}>
          <h2 className="m-0 text-xs font-semibold uppercase tracking-wider text-eyebrow">{s.label}</h2>
          <ValueList rows={s.rows} />
        </section>
      ))}
    </>
  );
}
