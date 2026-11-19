export interface ApiError {
  status: number;
  error: string;
  message: string;
}

// A governed action's answer, returned with HTTP 200 whether the proposal was accepted or
// rejected (spec/error-handling-contract-v1.md section 3.2). A rejection is a result, not an
// ApiError: the component that made the proposal shows it.
export interface Rejection {
  rule_id: string;
  message: string;
  retryable: boolean;
  ids?: Array<string | number>;
}

export type GovernedOutcome<TResult = Record<string, unknown>> =
  | {
      contract_version: string;
      decision: 'accepted';
      result: TResult;
      audit_id: number;
    }
  | {
      contract_version: string;
      decision: 'rejected';
      rejections: Rejection[];
      audit_id: number;
    };

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
  contract_version?: string;
}

export function isApiError(value: unknown): value is ApiError {
  return typeof value === 'object'
    && value !== null
    && 'status' in value
    && 'error' in value
    && 'message' in value;
}
