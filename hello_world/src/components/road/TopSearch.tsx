import { useState } from 'react';
import type { FormEvent } from 'react';
import { Search } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

// The top bar's search box. It opens Todos with the words filled in; that page does the search.
export function TopSearch() {
  const navigate = useNavigate();
  const [q, setQ] = useState('');

  function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    navigate(q.trim() ? `/todos?q=${encodeURIComponent(q.trim())}` : '/todos');
  }

  return (
    <form className="hidden w-64 items-center gap-2 rounded-lg border border-border bg-background px-3 focus-within:ring-3 focus-within:ring-ring/40 lg:flex" aria-label="Search all todos" onSubmit={submit} role="search">
      <Search aria-hidden="true" className="size-4 text-muted-foreground" />
      <label className="sr-only" htmlFor="top-search">Search todos</label>
      <input
        className="h-9 min-w-0 flex-1 border-0 bg-transparent text-sm outline-none"
        id="top-search"
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search todos"
        type="search"
        value={q}
      />
    </form>
  );
}
