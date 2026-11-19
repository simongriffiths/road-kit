import { NavLink } from 'react-router-dom';

import { app } from '../../config/app';
import { appIcons } from './icons';

// The main sections, from src/config/app.ts, as a row of links (top bar), a column (sidebar) or a
// bottom tab bar (below 768 px). aria-current is set on the current page by NavLink.
export function NavLinks({ variant }: { variant: 'row' | 'column' | 'tabs' }) {
  return (
    <nav
      aria-label="Main"
      className={{
        row: 'flex items-center gap-1',
        column: 'flex flex-col gap-0.5',
        tabs: 'flex border-t border-border bg-card px-2 pb-[env(safe-area-inset-bottom)] pt-1.5'
      }[variant]}
    >
      {app.nav.map((n) => {
        const Icon = appIcons[n.icon];
        return (
          <NavLink
            className={({ isActive }) => (variant === 'tabs'
              ? `flex min-h-12 flex-1 flex-col items-center justify-center gap-0.5 rounded-md text-[11px] no-underline ${isActive ? 'font-semibold text-primary' : 'text-muted-foreground'}`
              : `flex min-h-9 items-center gap-2.5 rounded-lg px-3 text-sm no-underline ${isActive ? 'bg-secondary font-semibold text-foreground' : 'text-ink-soft hover:bg-hover'}`)}
            end={n.to === '/'}
            key={n.to}
            to={n.to}
          >
            <Icon aria-hidden="true" className={variant === 'tabs' ? 'size-5' : 'size-4'} />
            {n.label}
          </NavLink>
        );
      })}
    </nav>
  );
}
