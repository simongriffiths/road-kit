import { apiRequest } from './client';
import type { GovernedOutcome } from '../types/api';

// The governed todo surface (spec-patch-16). The list carries one read token that every action on
// its rows sends back. Creating needs an Idempotency-Key; the other actions are keyed on the
// principal, the todo and the read token, so they send none.

export type TodoStatus = 'OPEN' | 'DONE';

export interface Todo {
  todo_id: number;
  title: string;
  notes: string | null;
  due_at: string | null;
  status: 'OPEN' | 'DONE' | 'DELETED';
  created_at: string;
  updated_at: string;
}

export interface TodoList {
  items: Todo[];
  hasMore: boolean;
  limit: number;
  offset: number;
  count: number;
  read_token: string;
}

export interface TodoFields {
  title: string;
  notes: string | null;
  due_at: string | null;
}

export const PAGE_SIZE = 25;

export const newKey = () => crypto.randomUUID();

const json = { 'Content-Type': 'application/json' };

export function listTodos(status: TodoStatus, query: string, offset: number) {
  const p = new URLSearchParams({ status, limit: String(PAGE_SIZE), offset: String(offset) });
  if (query.trim()) p.set('query', query.trim());
  return apiRequest<TodoList>(`/todos/?${p.toString()}`);
}

export function createTodo(fields: { title: string; notes?: string; due_at?: string }, key: string) {
  return apiRequest<GovernedOutcome>('/todos/', {
    method: 'POST',
    headers: { ...json, 'Idempotency-Key': key },
    body: JSON.stringify(fields)
  });
}

export function reviseTodo(id: number, readToken: string, changes: Partial<TodoFields>) {
  return apiRequest<GovernedOutcome>(`/todos/${id}/revisions/`, {
    method: 'POST',
    headers: json,
    body: JSON.stringify({ read_token: readToken, ...changes })
  });
}

export const completeTodo = (id: number, readToken: string) =>
  apiRequest<GovernedOutcome>(`/todos/${id}/completions/`, {
    method: 'POST',
    headers: json,
    body: JSON.stringify({ read_token: readToken })
  });

export const reopenTodo = (id: number, readToken: string) =>
  apiRequest<GovernedOutcome>(`/todos/${id}/reopenings/`, {
    method: 'POST',
    headers: json,
    body: JSON.stringify({ read_token: readToken })
  });

export const deleteTodo = (id: number, readToken: string) =>
  apiRequest<GovernedOutcome>(`/todos/${id}/`, {
    method: 'DELETE',
    headers: json,
    body: JSON.stringify({ read_token: readToken })
  });
