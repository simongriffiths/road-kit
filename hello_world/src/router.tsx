import { Navigate, createBrowserRouter } from 'react-router-dom';

import { App } from './App';
import { RequireAuth } from './components/RequireAuth';
import { HomePage } from './pages/HomePage';
import { LoginPage } from './pages/LoginPage';
import { SessionPage } from './pages/SessionPage';

const appName = import.meta.env.VITE_APP_NAME;
const uiBasePath = import.meta.env.VITE_UI_BASE_PATH;

export const router = createBrowserRouter(
  [
    {
      path: '/',
      element: <App />,
      children: [
        {
          path: 'index.html',
          element: <Navigate replace to="/" />
        },
        {
          path: '',
          element: <HomePage />
        },
        {
          path: 'login',
          element: <LoginPage />
        },
        {
          element: <RequireAuth />,
          children: [
            {
              path: 'session',
              element: <SessionPage />
            }
          ]
        }
      ]
    }
  ],
  {
    basename: `/ords/${uiBasePath}/ui/${appName}`
  }
);
