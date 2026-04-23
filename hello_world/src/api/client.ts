import type { ApiError } from '../types/api';
import { getOrdsBaseUrl } from '../config/runtime';
import { getToken } from '../utils/auth';

function buildError(status: number, error: string, message: string): ApiError {
  return { status, error, message };
}

export async function apiRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers = new Headers(options.headers);

  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${getOrdsBaseUrl()}${path}`, {
    ...options,
    headers
  });

  const payload = await response.json().catch(() => null);

  if (!response.ok) {
    throw buildError(
      response.status,
      typeof payload?.code === 'string' ? payload.code : 'HTTP_ERROR',
      typeof payload?.message === 'string'
        ? payload.message
        : `Request failed with status ${response.status}`
    );
  }

  return payload as T;
}
