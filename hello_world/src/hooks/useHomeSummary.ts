import { useCallback, useEffect, useState } from 'react';

import { listAgents } from '../api/agents';
import type { Agent } from '../api/agents';
import { completeTodo, listTodos } from '../api/todos';
import type { Todo } from '../api/todos';
import { isApiError } from '../types/api';
import { dueBucket } from '../utils/dates';
import { isAccepted, refusalText } from '../utils/outcome';

// What Home shows (spec-patch-18 section 7.2): the counts and the due list come from one read of
// up to 100 open todos, the API's maximum, so a long list is said to be cut off, not guessed at.

export const HOME_LIMIT = 100;

export function useHomeSummary() {
  const [todos, setTodos] = useState<Todo[] | null>(null);
  const [readToken, setReadToken] = useState('');
  const [more, setMore] = useState(false);
  const [agents, setAgents] = useState<Agent[] | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const r = await listTodos('OPEN', '', 0, HOME_LIMIT);
      setTodos(r.items);
      setReadToken(r.read_token);
      setMore(r.hasMore);
    } catch (e) {
      setNotice(isApiError(e) ? 'Could not read your todos.' : 'Something went wrong reading your todos.');
      setTodos([]);
    }
    try {
      const a = await listAgents();
      setAgents(a.agents.filter((x) => x.status === 'ACTIVE'));
    } catch {
      setAgents([]);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function complete(id: number) {
    try {
      const o = await completeTodo(id, readToken);
      setNotice(isAccepted(o) ? null : refusalText(o));
    } catch {
      setNotice('Something went wrong. Nothing was changed; try again.');
    }
    await load();
  }

  const open = todos ?? [];
  const overdue = open.filter((t) => dueBucket(t.due_at) === 'overdue');
  const today = open.filter((t) => dueBucket(t.due_at) === 'today');
  const dueList = [...overdue, ...today].slice(0, 8);

  return { todos, more, agents, notice, complete, counts: { open: open.length, today: today.length, overdue: overdue.length }, dueList };
}
