import { Navigate, createBrowserRouter } from 'react-router-dom';

import { AppShell } from './components/road/AppShell';
import { RequireAuth } from './components/RequireAuth';
import { ROUTER_BASENAME } from './config/runtime';
import { AgentsPage } from './pages/AgentsPage';
import { HomePage } from './pages/HomePage';
import { LoginPage } from './pages/LoginPage';
import { SessionPage } from './pages/SessionPage';
import { TodosPage } from './pages/TodosPage';

// Sign in sits outside the shell. Every other screen needs a token and renders inside AppShell
// (spec-patch-18 section 8).
export const router = createBrowserRouter(
  [
    { path: '/index.html', element: <Navigate replace to="/" /> },
    { path: '/login', element: <LoginPage /> },
    {
      element: <RequireAuth />,
      children: [
        {
          element: <AppShell />,
          children: [
            { path: '/', element: <HomePage /> },
            { path: '/session', element: <SessionPage /> },
            { path: '/agents', element: <AgentsPage /> },
            { path: '/todos', element: <TodosPage /> }
          ]
        }
      ]
    }
  ],
  { basename: ROUTER_BASENAME }
);
