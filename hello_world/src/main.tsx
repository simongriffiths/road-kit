import React from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';

import { router } from './router';
// theme.css sets up Tailwind, maps shadcn's variables onto tokens.css and loads brand.css (ADR 02).
import './theme.css';
import './hooks/useTheme';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
