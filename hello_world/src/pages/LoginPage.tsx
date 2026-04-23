import { FormEvent, useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';

import { loginRequest } from '../api/auth';
import { isApiError } from '../types/api';
import { getToken, setToken } from '../utils/auth';

export function LoginPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const [username, setUsername] = useState('ADMIN');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (getToken()) {
    return <Navigate replace to="/session" />;
  }

  const from = typeof location.state?.from === 'string'
    ? location.state.from
    : '/session';

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setErrorMessage(null);

    try {
      const response = await loginRequest(username, password);
      setToken(response.access_token);
      navigate(from, { replace: true });
    } catch (error) {
      if (isApiError(error)) {
        setErrorMessage(error.message);
      } else {
        setErrorMessage('Login failed unexpectedly.');
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="stack">
      <div className="section-heading">
        <h2>Login</h2>
        <p className="muted">
          This development scaffold exchanges username and password for a JWT and stores the token in
          session storage.
        </p>
      </div>

      <form className="auth-form" onSubmit={handleSubmit}>
        <label className="field">
          <span>Username</span>
          <input
            autoComplete="username"
            name="username"
            onChange={(event) => setUsername(event.target.value)}
            required
            value={username}
          />
        </label>

        <label className="field">
          <span>Password</span>
          <input
            autoComplete="current-password"
            name="password"
            onChange={(event) => setPassword(event.target.value)}
            required
            type="password"
            value={password}
          />
        </label>

        {errorMessage ? <p className="notice error">{errorMessage}</p> : null}

        <div className="row">
          <button className="button" disabled={submitting} type="submit">
            {submitting ? 'Signing In...' : 'Sign In'}
          </button>
          <p className="muted">Successful login redirects to the protected session page.</p>
        </div>
      </form>
    </div>
  );
}
