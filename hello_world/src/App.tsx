import { Link, NavLink, Outlet, useNavigate } from 'react-router-dom';

import { clearToken, getToken } from './utils/auth';

export function App() {
  const navigate = useNavigate();
  const hasToken = getToken() !== null;

  function handleLogout() {
    clearToken();
    navigate('/login');
  }

  return (
    <main className="app-shell">
      <header className="hero">
        <div className="masthead">
          <p className="eyebrow">ROAD Stage 3</p>
          <div className="nav-actions">
            <NavLink className="nav-link" to="/">Home</NavLink>
            <NavLink className="nav-link" to="/login">Login</NavLink>
            <NavLink className="nav-link" to="/session">Session</NavLink>
            {hasToken ? (
              <button className="button ghost" onClick={handleLogout} type="button">
                Log Out
              </button>
            ) : null}
          </div>
        </div>
        <h1>Hello World</h1>
        <p className="lede">
          Minimal hosted React shell proving public and protected routing against the ROAD ORDS auth
          scaffold.
        </p>
        <p className="status-line">
          Token status:
          {' '}
          <strong>{hasToken ? 'present in session storage' : 'not authenticated'}</strong>
          .
          {' '}
          <Link to="/session">Protected session route</Link>
        </p>
      </header>
      <section className="panel">
        <Outlet />
      </section>
    </main>
  );
}
