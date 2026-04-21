export interface ApiError {
  status: number;
  error: string;
  message: string;
}

export function isApiError(value: unknown): value is ApiError {
  return typeof value === 'object'
    && value !== null
    && 'status' in value
    && 'error' in value
    && 'message' in value;
}
