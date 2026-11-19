import { useSyncExternalStore } from 'react';

// Light, dark, or follow the system (spec-patch-18 section 4, ADR 02 ruling 3). The choice is kept
// in localStorage under 'road-theme'. The 'dark' class on <html> is the one switch tokens.css and
// theme.css key on. index.html runs the same rule before the first paint.

export type ThemeChoice = 'light' | 'dark' | 'system';
const KEY = 'road-theme';
const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)') : null;
const listeners = new Set<() => void>();

function readChoice(): ThemeChoice {
  try {
    const v = localStorage.getItem(KEY);
    return v === 'light' || v === 'dark' ? v : 'system';
  } catch {
    return 'system';
  }
}

let choice: ThemeChoice = readChoice();

function isDark(c: ThemeChoice): boolean {
  return c === 'dark' || (c === 'system' && !!media?.matches);
}

function apply() {
  const dark = isDark(choice);
  document.documentElement.classList.toggle('dark', dark);
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
  listeners.forEach((l) => l());
}

media?.addEventListener('change', apply);
apply();

function setChoice(next: ThemeChoice) {
  choice = next;
  try {
    if (next === 'system') localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, next);
  } catch {
    // Storage may be blocked; the choice then lasts until reload.
  }
  apply();
}

// A snapshot string changes whenever the choice or the system setting does.
const snapshot = () => `${choice}:${isDark(choice) ? 'dark' : 'light'}`;
const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

export function useTheme() {
  const [c, resolved] = useSyncExternalStore(subscribe, snapshot, snapshot).split(':') as [ThemeChoice, 'light' | 'dark'];
  return { choice: c, resolved, setChoice };
}
