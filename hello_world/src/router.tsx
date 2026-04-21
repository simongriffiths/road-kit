import { createBrowserRouter } from 'react-router-dom';

import { App } from './App';
import { HomePage } from './pages/HomePage';

const appName = import.meta.env.VITE_APP_NAME;
const uiBasePath = import.meta.env.VITE_UI_BASE_PATH;

export const router = createBrowserRouter(
  [
    {
      path: '/',
      element: <App />,
      children: [
        {
          path: '',
          element: <HomePage />
        }
      ]
    }
  ],
  {
    basename: `/ords/${uiBasePath}/ui/${appName}`
  }
);
