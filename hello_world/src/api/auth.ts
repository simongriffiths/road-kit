import type { ApiError, LoginResponse } from '../types/api';
import { getAuthBaseUrl } from '../config/runtime';

function buildError(status: number, error: string, message: string): ApiError {
  return { status, error, message };
}

export async function loginRequest(
  username: string,
  password: string
): Promise<LoginResponse> {
  const response = await fetch(`${getAuthBaseUrl()}/jwt-auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ username, password })
  });

  const payload = await response.json().catch(() => null);

  if (!response.ok) {
    throw buildError(
      response.status,
      typeof payload?.error === 'string' ? payload.error : 'HTTP_ERROR',
      typeof payload?.error_description === 'string'
        ? payload.error_description
        : `Request failed with status ${response.status}`
    );
  }

  return payload as LoginResponse;
}
