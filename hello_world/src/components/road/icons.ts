import { Bot, House, ListChecks } from 'lucide-react';

// The icons a nav item may name in src/config/app.ts. Add a line to offer another.
export const appIcons = { home: House, list: ListChecks, bot: Bot };
export type AppIconName = keyof typeof appIcons;
