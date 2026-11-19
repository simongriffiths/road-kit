import { useCallback, useEffect, useRef, useState } from 'react';

import {
  PAGE_SIZE, completeTodo, createTodo, deleteTodo, listTodos, newKey, reopenTodo, reviseTodo
} from '../api/todos';
import type { Todo, TodoFields, TodoStatus } from '../api/todos';
import { isApiError } from '../types/api';
import type { GovernedOutcome } from '../types/api';
import { isAccepted, isStale, refusalText } from '../utils/outcome';

// The todo list, its read token, paging, tab and search, and the actions (spec-patch-17 3.1 to 3.5).
// Every answer goes through settle(), the one place that reads it. Returns whether the action was
// accepted, and whether the answer was a stale token, so a form can decide what to keep.

export interface Settled {
  accepted: boolean;
  stale: boolean;
}

const STALE_NOTICE =
  'Someone changed this todo while you were looking. The list now shows the change. If you were editing, '
  + 'your edit is still in the form; save it again if it is still right.';

function errorNotice(e: unknown): string {
  if (isApiError(e)) {
    if (e.status === 403) return 'You are not allowed to do that.';
    if (e.status === 400) return e.message;
  }
  return 'Something went wrong. Nothing was changed by this page; try again.';
}

export function useTodos() {
  const [status, setTabState] = useState<TodoStatus>('OPEN');
  const [query, setQueryState] = useState('');
  const [items, setItems] = useState<Todo[] | null>(null);
  const [readToken, setReadToken] = useState('');
  const [hasMore, setHasMore] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [createKey, setCreateKey] = useState(newKey());
  const loaded = useRef(0);
  const latest = useRef(0);

  // Fetches the first page, or every page seen so far when `keep` is set, so an action does not
  // send the person back to the top of a long list.
  const load = useCallback(async (keep = false) => {
    const ticket = ++latest.current;
    const want = keep ? Math.max(loaded.current, PAGE_SIZE) : PAGE_SIZE;
    try {
      const r = await listTodos(status, query, 0);
      let all = r.items;
      let more = r.hasMore;
      while (all.length < want && more) {
        const next = await listTodos(status, query, all.length);
        all = all.concat(next.items);
        more = next.hasMore;
      }
      if (ticket !== latest.current) return;
      loaded.current = all.length;
      setItems(all);
      setReadToken(r.read_token);
      setHasMore(more);
    } catch (e) {
      if (ticket !== latest.current) return;
      setNotice(errorNotice(e));
      setItems((was) => was ?? []);
    }
  }, [status, query]);

  useEffect(() => {
    setItems(null);
    void load();
  }, [load]);

  const showMore = useCallback(async () => {
    try {
      const r = await listTodos(status, query, loaded.current);
      loaded.current += r.items.length;
      setItems((was) => (was ?? []).concat(r.items));
      setHasMore(r.hasMore);
    } catch (e) {
      setNotice(errorNotice(e));
    }
  }, [status, query]);

  async function settle(work: () => Promise<GovernedOutcome>): Promise<Settled> {
    try {
      const o = await work();
      if (isAccepted(o)) {
        setNotice(null);
        await load(true);
        return { accepted: true, stale: false };
      }
      const stale = isStale(o);
      setNotice(stale ? STALE_NOTICE : refusalText(o));
      await load(true);
      return { accepted: false, stale };
    } catch (e) {
      setNotice(errorNotice(e));
      return { accepted: false, stale: false };
    }
  }

  const add = async (fields: { title: string; notes?: string; due_at?: string }) => {
    const s = await settle(() => createTodo(fields, createKey));
    if (s.accepted) setCreateKey(newKey());
    return s;
  };

  const revise = (id: number, changes: Partial<TodoFields>) => settle(() => reviseTodo(id, readToken, changes));
  const complete = (id: number) => settle(() => completeTodo(id, readToken));
  const reopen = (id: number) => settle(() => reopenTodo(id, readToken));
  const remove = (id: number) => settle(() => deleteTodo(id, readToken));

  const setTab = (s: TodoStatus) => { setNotice(null); setTabState(s); };
  const setQuery = (q: string) => { setQueryState(q); };

  return {
    status, query, items, hasMore, notice,
    setTab, setQuery, showMore, reload: () => load(true),
    add, revise, complete, reopen, remove
  };
}
