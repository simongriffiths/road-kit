export interface ApiError {
  status: number;
  error: string;
  message: string;
}

export interface LoginResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  kid: string;
}

export interface SessionIdentity {
  principal: string;
  issuer: string;
  audience: string;
  scope: string;
  authenticated: string;
  current_user: string;
  db_user: string;
}

export function isApiError(value: unknown): value is ApiError {
  return typeof value === 'object'
    && value !== null
    && 'status' in value
    && 'error' in value
    && 'message' in value;
}
