// Due dates are dates, not times (spec-patch-17 7.7). The page sends local midnight with the
// browser's offset and shows the date only.

const pad = (n: number) => String(n).padStart(2, '0');

export function dateToDueAt(date: string): string {
  const [y, m, d] = date.split('-').map(Number);
  const local = new Date(y, m - 1, d);
  const offset = -local.getTimezoneOffset();
  const sign = offset < 0 ? '-' : '+';
  const abs = Math.abs(offset);
  return `${date}T00:00:00${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

export function dueAtToDate(dueAt: string | null): string {
  if (!dueAt) return '';
  const d = new Date(dueAt);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export const showDate = (dueAt: string) => new Date(dueAt).toLocaleDateString();
