import { Link } from 'react-router-dom';

import { getOrdsBaseUrl } from '../config/runtime';

export function HomePage() {
  return (
    <div className="stack">
      <div className="section-heading">
        <h2>Bootstrap Ready</h2>
        <p>
          The application is configured to build for
          {' '}
          <code>/ords/{import.meta.env.VITE_UI_BASE_PATH}/ui/{import.meta.env.VITE_APP_NAME}/</code>
          .
        </p>
      </div>
      <div className="card-grid">
        <div className="card">
          <h3>Public Route</h3>
          <p className="muted">
            This home page remains public and can be loaded without a token.
          </p>
          <Link className="button secondary" to="/login">Go To Login</Link>
        </div>
        <div className="card">
          <h3>Protected Route</h3>
          <p className="muted">
            The session page redirects to login unless a token has already been stored.
          </p>
          <Link className="button" to="/session">View Session</Link>
        </div>
      </div>
      <dl className="kv">
        <div>
          <dt>App Name</dt>
          <dd>{import.meta.env.VITE_APP_NAME}</dd>
        </div>
        <div>
          <dt>UI Base Path</dt>
          <dd>{import.meta.env.VITE_UI_BASE_PATH}</dd>
        </div>
        <div>
          <dt>API Base URL</dt>
          <dd>{getOrdsBaseUrl()}</dd>
        </div>
      </dl>
    </div>
  );
}
