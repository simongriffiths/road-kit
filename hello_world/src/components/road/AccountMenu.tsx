import type { Ref } from 'react';
import { Bot, ChevronDown, Info, LogOut, Monitor, Moon, ScrollText, Sun } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

import { useTheme } from '../../hooks/useTheme';
import type { ThemeChoice } from '../../hooks/useTheme';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuRadioGroup, DropdownMenuRadioItem,
  DropdownMenuSeparator, DropdownMenuTrigger
} from '../ui/dropdown-menu';
import type { DrawerTab } from './SessionDrawer';

// The signed-in person's menu (spec-patch-18 section 6): session details, agents, the theme and
// sign out. The button shows the principal, because the session read returns no display name.
export function AccountMenu({ principal, onOpenDrawer, onSignOut, triggerRef }: {
  principal: string | null;
  onOpenDrawer: (tab: DrawerTab) => void;
  onSignOut: () => void;
  triggerRef: Ref<HTMLButtonElement>;
}) {
  const navigate = useNavigate();
  const { choice, setChoice } = useTheme();
  const initials = (principal ?? '?').slice(0, 2).toUpperCase();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className="inline-flex min-h-11 max-w-60 items-center gap-2.5 rounded-full border border-border bg-card py-1 pl-1 pr-3 text-left outline-none hover:bg-hover focus-visible:ring-3 focus-visible:ring-ring/50"
        ref={triggerRef}
      >
        <span className="sr-only">Account menu, </span>
        <span aria-hidden="true" className="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-xs font-bold text-primary-strong">{initials}</span>
        <span className="hidden min-w-0 flex-col leading-tight sm:flex">
          <span className="truncate text-[13px] font-semibold">{principal ?? 'Signed in'}</span>
          <span className="text-xs text-muted-foreground">Signed in</span>
        </span>
        <ChevronDown aria-hidden="true" className="size-3.5 text-muted-foreground" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-64">
        <div className="px-2 py-2">
          <div className="truncate text-sm font-semibold">{principal ?? 'Signed in'}</div>
          <div className="text-xs text-muted-foreground">Signed in</div>
        </div>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => onOpenDrawer('session')}><Info /> Session details</DropdownMenuItem>
        <DropdownMenuItem onClick={() => onOpenDrawer('contract')}><ScrollText /> API and contract</DropdownMenuItem>
        <DropdownMenuItem onClick={() => navigate('/agents')}><Bot /> My agents</DropdownMenuItem>
        <DropdownMenuSeparator />
        <div className="px-2 pb-1 pt-1.5 text-xs text-muted-foreground">Theme</div>
        <DropdownMenuRadioGroup onValueChange={(v) => setChoice(v as ThemeChoice)} value={choice}>
          <DropdownMenuRadioItem value="light"><Sun /> Light</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="dark"><Moon /> Dark</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="system"><Monitor /> System</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={onSignOut}><LogOut /> Sign out</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
