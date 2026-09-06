import React from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';

import { router } from './router';
// theme.css first: it sets up Tailwind and maps shadcn's variables onto tokens.css. styles.css is
// tier 2, retired by ADR 01 but still styling these screens until the component vocabulary lands.
import './theme.css';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
