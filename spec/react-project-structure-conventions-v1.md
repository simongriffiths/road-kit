# React Project Structure & Conventions
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines the standard structure and conventions for every React application in this framework. It ensures that all apps — whether demo applications or production apps — are consistent enough that a developer familiar with one can navigate any other.

---

## 2. Core Principles

1. **Consistency over cleverness.** Every app follows the same structure. Deviations require justification.
2. **Simple state management.** Use the simplest state mechanism that works. Avoid framework overhead until it is genuinely needed.
3. **Thin components.** Components handle rendering and user interaction. Business logic and API calls belong in hooks and services.
4. **One fetch wrapper.** All ORDS API calls go through the central fetch wrapper. No component calls `fetch` directly.
5. **Copy per app in v1.** Shared utilities are copied into each app. The interface is standardised so copies remain consistent.

---

## 3. Technology Baseline

| Concern | Decision |
|---|---|
| Framework | React (pure client-side, no SSR) |
| Language | TypeScript |
| Build tool | Vite |
| Component library | To be standardised — TBD |
| Styling | To be standardised — TBD |
| API calls | Central fetch wrapper (library TBD) |
| State management | React Context for global state, local state for component state |
| Routing | React Router |

Decisions marked TBD will be resolved before the first production app is built. Demo apps may use any reasonable choice but must conform once standardised.

---

## 4. Directory Structure

Every app must follow this structure:

```
<app-name>/
  src/
    api/
      client.ts           ← fetch wrapper
      <resource>.ts       ← per-resource API functions
    components/
      common/             ← shared UI components (notifications, layout)
      <feature>/          ← feature-specific components
    hooks/
      useAuth.ts          ← authentication hook
      use<Resource>.ts    ← per-resource data hooks
    context/
      AuthContext.tsx     ← authentication context and provider
      ErrorContext.tsx    ← global error/notification context and provider
    pages/
      <PageName>.tsx      ← top-level page components (one per route)
    types/
      api.ts              ← API response and error types
      <domain>.ts         ← domain model types
    utils/
      auth.ts             ← JWT storage and decode utilities
    App.tsx
    main.tsx
    router.tsx
  public/
  .env.development
  .env.test
  .env.production
  vite.config.ts
  tsconfig.json
  package.json
```

---

## 5. Environment Variables

### 5.1 Required Variables

Every app must define these variables in `.env.development`, `.env.test`, and `.env.production`:

```text
VITE_APP_NAME=<app_name>
VITE_UI_BASE_PATH=<ui_base_path>
VITE_ORDS_BASE_URL=https://<host>/ords/<api_base_path>/api/v1
```

### 5.2 Rules

- All environment variables exposed to the client must be prefixed `VITE_`
- Never put credentials, secrets, or JWT signing keys in environment variables
- `.env.development`, `.env.test`, and `.env.production` are committed to source control — they contain only non-sensitive configuration
- A `.env.example` must be included documenting all required variables
- `VITE_APP_NAME` must be derived from the repo-root `road.config` `APP_NAME` value so frontend routing and deployment identity match

### 5.3 Usage

- `VITE_APP_NAME` defines the application identity used in deployed UI paths
- `VITE_UI_BASE_PATH` defines the public ORDS UI path segment used to host the SPA, for example `road-ui`
- The deployed UI base URL is therefore `https://<host>/ords/<ui_base_path>/ui/<app_name>/`
- `VITE_ORDS_BASE_URL` must be accessed only through the API client
- Components and hooks must never reference `import.meta.env` directly

---

## 6. API Client

### 6.1 Location

```
src/api/client.ts
```

### 6.2 Responsibilities

The API client is the single point of contact with the ORDS backend. It must:

- Construct the full URL from `VITE_ORDS_BASE_URL` and the given path
- Attach the JWT `Authorization: Bearer <token>` header on every request where a token exists
- Detect non-2xx responses and throw a typed `ApiError`
- Parse JSON response bodies
- Handle JSON parse failures gracefully
- Dispatch 401 responses to the auth context (token clear + redirect)
- Dispatch 5xx and network errors to the error context (banner)
- Dispatch 4xx errors to the error context (toast)

### 6.3 ApiError Type

```typescript
// src/types/api.ts

export interface ApiError {
  status: number;
  error: string;
  message: string;
}

export function isApiError(value: unknown): value is ApiError {
  return (
    typeof value === 'object' &&
    value !== null &&
    'status' in value &&
    'error' in value &&
    'message' in value
  );
}
```

### 6.4 Client Interface

The client must expose a typed request function:

```typescript
// src/api/client.ts

export async function apiRequest<T>(
  path: string,
  options?: RequestInit
): Promise<T>
```

Callers receive the parsed response body on success or a thrown `ApiError` on failure.

### 6.5 Per-Resource API Modules

Each ORDS resource gets its own file under `src/api/`:

```typescript
// src/api/customers.ts

import { apiRequest } from './client';
import type { Customer, CustomerCollection } from '../types/customer';

export async function getCustomers(offset = 0, limit = 25): Promise<CustomerCollection> {
  return apiRequest(`/customers/?offset=${offset}&limit=${limit}`);
}

export async function getCustomerById(id: number): Promise<Customer> {
  return apiRequest(`/customers/${id}`);
}

export async function createCustomer(data: Partial<Customer>): Promise<Customer> {
  return apiRequest('/customers/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  });
}
```

No component may import from `client.ts` directly — only from per-resource API modules.

---

## 7. Authentication

### 7.1 JWT Storage

JWTs must be stored in `sessionStorage`, not `localStorage`. This limits exposure to the current browser tab session.

Key: `auth_token`

JWT storage and retrieval must go through `src/utils/auth.ts` only. No component or hook accesses `sessionStorage` directly.

```typescript
// src/utils/auth.ts

export function getToken(): string | null {
  return sessionStorage.getItem('auth_token');
}

export function setToken(token: string): void {
  sessionStorage.setItem('auth_token', token);
}

export function clearToken(): void {
  sessionStorage.removeItem('auth_token');
}
```

### 7.2 AuthContext

`src/context/AuthContext.tsx` must provide:

```typescript
interface AuthContextValue {
  isAuthenticated: boolean;
  user: AuthUser | null;
  login: (token: string) => void;
  logout: () => void;
}
```

`AuthContext` is the single source of truth for authentication state. Components must not read the JWT directly.

### 7.3 useAuth Hook

```typescript
// src/hooks/useAuth.ts
export function useAuth(): AuthContextValue
```

All components and hooks that need auth state must use `useAuth()`.

### 7.4 Protected Routes

Routes that require authentication must be wrapped in a `ProtectedRoute` component that redirects to the login page if `isAuthenticated` is false.

---

## 8. Global Error Handling

### 8.1 ErrorContext

`src/context/ErrorContext.tsx` must provide:

```typescript
interface ErrorContextValue {
  showToast: (message: string) => void;
  showBanner: (message: string) => void;
  dismissBanner: () => void;
}
```

### 8.2 Notification Components

**Toast** — lives in `src/components/common/Toast.tsx`

- Fixed position, bottom-right
- Auto-dismisses after 4 seconds
- Queue-safe (multiple toasts supported)
- Displays the `message` field from `ApiError`

**ErrorBanner** — lives in `src/components/common/ErrorBanner.tsx`

- Renders at the top of the page content area
- Requires manual dismissal
- Always displays a generic message for 5xx and network errors
- One banner at a time

Both components are rendered in `App.tsx` at the root level, outside of the router outlet, so they are always available regardless of current route.

### 8.3 API Client Integration

The API client dispatches errors to `ErrorContext` automatically. Components do not need to handle API errors — they only handle the success case.

Exception: forms may catch `ApiError` with status 400 or 422 to display inline field-level validation messages in addition to (or instead of) the global toast.

---

## 9. Component Conventions

### 9.1 File Naming

- Components: `PascalCase.tsx`
- Hooks: `camelCase.ts`, prefixed `use`
- Utilities: `camelCase.ts`
- Types: `camelCase.ts`
- API modules: `camelCase.ts`

### 9.2 Component Rules

- One component per file
- No API calls inside components — use hooks
- No direct `sessionStorage` / `localStorage` access in components
- No direct `import.meta.env` access in components
- Props interfaces must be explicitly typed — no `any`

### 9.3 Page Components

Page components live in `src/pages/` and map 1:1 to routes. They are responsible for:

- Composing feature components
- Passing data from hooks to components
- Top-level loading and empty states

Page components must not contain business logic or inline API calls.

### 9.4 Data Hooks

Per-resource data hooks live in `src/hooks/` and wrap the per-resource API modules:

```typescript
// src/hooks/useCustomers.ts

export function useCustomers() {
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(false);

  const fetchCustomers = async () => {
    setLoading(true);
    try {
      const result = await getCustomers();
      setCustomers(result.items);
    } finally {
      setLoading(false);
    }
  };

  return { customers, loading, fetchCustomers };
}
```

Hooks expose loading state, data, and action functions. They do not handle error display — the API client handles that globally.

---

## 10. Routing

Routes are defined in `src/router.tsx`:

```typescript
// src/router.tsx

const appName = import.meta.env.VITE_APP_NAME;
const uiBasePath = import.meta.env.VITE_UI_BASE_PATH;

const router = createBrowserRouter([
  {
    path: '/',
    element: <App />,
    children: [
      { path: 'login', element: <LoginPage /> },
      {
        element: <ProtectedRoute />,
        children: [
          { path: '', element: <HomePage /> },
          { path: 'customers', element: <CustomersPage /> },
          { path: 'customers/:id', element: <CustomerDetailPage /> },
        ]
      }
    ]
  }
], {
  basename: `/ords/${uiBasePath}/ui/${appName}`
});
```

Rules:

- The router must use a basename of `/ords/<ui_base_path>/ui/<app_name>`
- All authenticated routes must be children of `ProtectedRoute`
- Route paths use kebab-case for multi-word segments
- Route params use camelCase (`:customerId`, not `:customer_id`)
- `vite.config.ts` must set `base` to `/ords/<ui_base_path>/ui/<app_name>/` so built asset URLs resolve correctly under ORDS UI delivery
- `VITE_APP_NAME` and `VITE_UI_BASE_PATH` may be read only in bootstrap or routing/build configuration code such as `src/router.tsx`, `src/main.tsx`, or `vite.config.ts`
- The app must not assume it is hosted at `/`

---

## 11. TypeScript Conventions

- `strict: true` in `tsconfig.json`
- No `any` — use `unknown` and type guards where the type is genuinely unknown
- API response types must be defined in `src/types/` and match the ORDS response shape
- ORDS collection responses use a typed generic wrapper:

```typescript
// src/types/api.ts

export interface OrdsCollection<T> {
  items: T[];
  hasMore: boolean;
  limit: number;
  offset: number;
  count: number;
}
```

---

## 12. What This Spec Does Not Cover

- Component library and styling (TBD — to be added as an amendment when standardised)
- Testing conventions (see Automated Testing Strategy spec)
- Build and deployment (see CI/CD Pipeline spec)
- Authentication flow details (see `authentication-spec-v1.md`)
- File upload and UI delivery conventions beyond the app build output contract (see `file-upload-and-ui-delivery-spec-v1.md`)
