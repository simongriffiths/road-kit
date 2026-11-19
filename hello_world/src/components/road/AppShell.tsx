import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Outlet, useNavigate } from 'react-router-dom';

import { app } from '../../config/app';
import { useSession } from '../../hooks/useSession';
import { clearToken } from '../../utils/auth';
import { Toaster } from '../ui/sonner';
import { TooltipProvider } from '../ui/tooltip';
import { AccountMenu } from './AccountMenu';
import { AppMark } from './AppMark';
import { NavLinks } from './NavLinks';
import { SessionDrawer } from './SessionDrawer';
import type { DrawerTab } from './SessionDrawer';
import { TopSearch } from './TopSearch';

// The frame around every signed-in screen (spec-patch-18 section 6): a top bar or a sidebar, set in
// src/config/app.ts, with the main sections in a bottom tab bar below 768 px, a skip link, the
// account menu and the session drawer. Pages render into <Outlet />.
export function AppShell({ children }: { children?: ReactNode }) {
  const navigate = useNavigate();
  const sessionState = useSession(true);
  const [drawer, setDrawer] = useState<DrawerTab | null>(null);
  const accountRef = useRef<HTMLButtonElement>(null);
  const sidebar = app.layout === 'sidebar';

  useEffect(() => {
    document.documentElement.lang = 'en';
  }, []);

  function signOut() {
    clearToken();
    navigate('/login');
  }

  const account = (
    <AccountMenu
      onOpenDrawer={setDrawer}
      onSignOut={signOut}
      principal={sessionState.session?.principal ?? null}
      triggerRef={accountRef}
    />
  );

  return (
    <TooltipProvider>
      <div className="min-h-screen bg-background text-foreground">
        <a
          className="absolute left-2 top-2 z-50 -translate-y-16 rounded-md bg-card px-3 py-2 text-sm shadow-md focus:translate-y-0"
          href="#main"
        >
          Skip to content
        </a>

        <div className={sidebar ? 'md:flex' : ''}>
          {sidebar ? (
            <aside className="sticky top-0 hidden h-screen w-60 shrink-0 flex-col gap-5 border-r border-border bg-card p-3 md:flex">
              <div className="px-2 pt-1"><AppMark /></div>
              <NavLinks variant="column" />
              <div className="mt-auto">{account}</div>
            </aside>
          ) : null}

          <div className="min-w-0 flex-1">
            <header className={`flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-border bg-card px-4 py-2.5 sm:px-8 ${sidebar ? 'md:hidden' : ''}`}>
              <AppMark />
              {!sidebar ? <div className="hidden md:block"><NavLinks variant="row" /></div> : null}
              <div className="flex-1" />
              {!sidebar ? <TopSearch /> : null}
              {account}
            </header>

            <main className="mx-auto flex w-full max-w-[1180px] flex-col gap-7 px-4 pb-28 pt-8 outline-none sm:px-8 md:pb-14" id="main" tabIndex={-1}>
              {children ?? <Outlet />}
            </main>
          </div>
        </div>

        <div className="fixed inset-x-0 bottom-0 z-30 md:hidden"><NavLinks variant="tabs" /></div>

        <SessionDrawer
          onClose={() => setDrawer(null)}
          onTabChange={setDrawer}
          returnFocusTo={accountRef}
          state={sessionState}
          tab={drawer}
        />
        <Toaster position="bottom-right" />
      </div>
    </TooltipProvider>
  );
}
