import type { ApiError } from '../types/api';
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

  const response = await fetch(`${import.meta.env.VITE_ORDS_BASE_URL}${path}`, {
    ...options,
    headers
  });

  if (!response.ok) {
    throw buildError(response.status, 'HTTP_ERROR', `Request failed with status ${response.status}`);
  }

  return response.json() as Promise<T>;
}
