import { apiRequest } from './client';
import type { GovernedOutcome } from '../types/api';

// Agents and their API keys (spec-patch-15). Changes are governed actions: HTTP 200 with the
// decision in the body. Each carries a fresh Idempotency-Key; a retry of the same proposal reuses it.

export interface AgentKey {
  key_id: number;
  name: string;
  key_prefix: string;
  created_at: string;
  last_used_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
}

export interface Agent {
  agent_id: number;
  subject: string;
  display_name: string;
  status: 'ACTIVE' | 'SUSPENDED' | 'RETIRED';
  owner: string | null;
  created_at: string;
  keys: AgentKey[] | null;
}

export const newKey = () => crypto.randomUUID();

const post = (path: string, body: unknown, key: string) =>
  apiRequest<GovernedOutcome>(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
    body: JSON.stringify(body)
  });

export function listAgents(all = false) {
  return apiRequest<{ agents: Agent[]; self_serve: boolean }>(`/agents/${all ? '?all=true' : ''}`);
}

export function createAgent(displayName: string, key = newKey()) {
  return post('/agents/', { display_name: displayName }, key) as Promise<GovernedOutcome<{ agent_id: number; subject: string }>>;
}

export function retireAgent(agentId: number, key = newKey()) {
  return apiRequest<GovernedOutcome>(`/agents/${agentId}/`, { method: 'DELETE', headers: { 'Idempotency-Key': key } });
}

export function createKey(agentId: number, name: string, key = newKey()) {
  return post(`/agents/${agentId}/keys/`, { name }, key) as Promise<GovernedOutcome<{ key_id: number; api_key?: string }>>;
}

export function revokeKey(agentId: number, keyId: number, key = newKey()) {
  return apiRequest<GovernedOutcome>(`/agents/${agentId}/keys/${keyId}/`, { method: 'DELETE', headers: { 'Idempotency-Key': key } });
}
