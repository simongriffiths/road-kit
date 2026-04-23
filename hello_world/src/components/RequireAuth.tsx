import { Navigate, Outlet, useLocation } from 'react-router-dom';

import { getToken } from '../utils/auth';

export function RequireAuth() {
  const location = useLocation();
  const token = getToken();

  if (!token) {
    return (
      <Navigate
        replace
        to="/login"
        state={{ from: `${location.pathname}${location.search}` }}
      />
    );
  }

  return <Outlet />;
}
