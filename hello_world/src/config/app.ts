// This app's identity (ADR 02, spec-patch-18 section 5). Owned by the app: a fork edits this file
// and src/brand.css, and nothing else, to look like its own product.

import type { AppIconName } from '../components/road/icons';

export interface NavItem {
  to: string;
  label: string;
  icon: AppIconName;
}

export const app = {
  name: 'Hello World',
  description: 'One todo list for you and the agents you approve.',
  // 'topbar' suits up to about six sections; 'sidebar' suits more.
  layout: 'topbar' as 'topbar' | 'sidebar',
  nav: [
    { to: '/', label: 'Home', icon: 'home' },
    { to: '/todos', label: 'Todos', icon: 'list' },
    { to: '/agents', label: 'Agents', icon: 'bot' }
  ] as NavItem[],
  points: [
    'Agents get their own API keys, and you can revoke one at any time.',
    'If a todo changed while you were editing it, your edit is kept and you are told.',
    'When the database refuses a change, you see its reason in plain words.'
  ]
};

export function pageTitle(page?: string): string {
  return page ? `${page} · ${app.name}` : app.name;
}
