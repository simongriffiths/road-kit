import type { ApiError } from '../types/api';
import { API_VERSION, getOrdsBaseUrl } from '../config/runtime';
import { clearToken, getToken } from '../utils/auth';

function buildError(status: number, error: string, message: string): ApiError {
  return { status, error, message };
}

export async function apiRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers = new Headers(options.headers);
  headers.set('Accept-Version', API_VERSION);

  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${getOrdsBaseUrl()}${path}`, {
    ...options,
    headers
  });

  const payload = await response.json().catch(() => null);

  // spec/error-handling-contract-v1.md 6.5: on a 401 clear the token and go to Login, with no banner.
  // A 401 from a call made without a token (the sign-in itself) is a wrong password, not an expiry.
  if (response.status === 401 && token) {
    clearToken();
    window.location.assign(`${import.meta.env.BASE_URL}login`);
  }

  if (!response.ok) {
    throw buildError(
      response.status,
      typeof payload?.error === 'string' ? payload.error : 'HTTP_ERROR',
      typeof payload?.message === 'string'
        ? payload.message
        : `Request failed with status ${response.status}`
    );
  }

  return payload as T;
}
