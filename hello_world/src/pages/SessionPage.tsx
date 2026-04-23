import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import { apiRequest } from '../api/client';
import type { SessionIdentity } from '../types/api';
import { isApiError } from '../types/api';
import { clearToken } from '../utils/auth';

export function SessionPage() {
  const navigate = useNavigate();
  const [session, setSession] = useState<SessionIdentity | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadSession() {
      try {
        const response = await apiRequest<SessionIdentity>('/session/me/');

        if (!cancelled) {
          setSession(response);
        }
      } catch (error) {
        if (cancelled) {
          return;
        }

        if (isApiError(error) && error.status === 401) {
          clearToken();
          navigate('/login', {
            replace: true,
            state: { from: '/session' }
          });
          return;
        }

        if (isApiError(error)) {
          setErrorMessage(error.message);
        } else {
          setErrorMessage('Failed to load session details.');
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadSession();

    return () => {
      cancelled = true;
    };
  }, [navigate]);

  if (loading) {
    return <p className="muted">Loading protected session data...</p>;
  }

  if (errorMessage) {
    return (
      <div className="stack">
        <div className="section-heading">
          <h2>Protected Session</h2>
          <p className="muted">
            The route is protected, but the API call still failed after the token was attached.
          </p>
        </div>
        <p className="notice error">{errorMessage}</p>
      </div>
    );
  }

  if (!session) {
    return <p className="notice error">No session data was returned.</p>;
  }

  return (
    <div className="stack">
      <div className="section-heading">
        <h2>Protected Session</h2>
        <p className="muted">
          This page proves that the browser token, ORDS privilege enforcement, and PL/SQL session mapping
          are aligned.
        </p>
      </div>

      <dl className="kv">
        <div>
          <dt>Principal</dt>
          <dd>{session.principal}</dd>
        </div>
        <div>
          <dt>Scope</dt>
          <dd>{session.scope}</dd>
        </div>
        <div>
          <dt>Issuer</dt>
          <dd>{session.issuer}</dd>
        </div>
        <div>
          <dt>Audience</dt>
          <dd>{session.audience}</dd>
        </div>
        <div>
          <dt>Authenticated</dt>
          <dd>{session.authenticated}</dd>
        </div>
        <div>
          <dt>Current User</dt>
          <dd>{session.current_user}</dd>
        </div>
      </dl>
    </div>
  );
}
