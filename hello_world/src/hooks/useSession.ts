import { useCallback, useEffect, useState } from 'react';

import { apiRequest } from '../api/client';
import { isApiError } from '../types/api';
import type { SessionIdentity } from '../types/api';

// What the database knows about this sign-in, from GET /session/me/ (spec-patch-18 section 6.1).
// `enabled` lets the drawer read only when it is open. A 401 is handled in apiRequest.

export function useSession(enabled = true) {
  const [session, setSession] = useState<SessionIdentity | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [readAt, setReadAt] = useState<Date | null>(null);
  const [loading, setLoading] = useState(false);

  const read = useCallback(async () => {
    setLoading(true);
    try {
      setSession(await apiRequest<SessionIdentity>('/session/me/'));
      setError(null);
      setReadAt(new Date());
    } catch (e) {
      setError(isApiError(e) ? e.message : 'Could not read the session.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (enabled) void read();
  }, [enabled, read]);

  return { session, error, readAt, loading, read };
}
