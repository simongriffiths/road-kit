// The contract major version this client speaks (spec-patch-17 7.6). A later major version answers
// 400 VERSION_MISMATCH, so a copied template fails clearly instead of quietly.
export const API_VERSION = '0';

// Build-time identity of this deployment (the drawer's Connection tab, the router's base path).
export const APP_NAME: string = import.meta.env.VITE_APP_NAME;
export const UI_BASE_PATH: string = import.meta.env.VITE_UI_BASE_PATH;
export const ROUTER_BASENAME = `/ords/${UI_BASE_PATH}/ui/${APP_NAME}`;

export function getOrdsBaseUrl(): string {
  const configuredUrl = import.meta.env.VITE_ORDS_BASE_URL;

  if (configuredUrl.includes('<host>')) {
    return configuredUrl.replace('https://<host>', window.location.origin);
  }

  if (configuredUrl.startsWith('/')) {
    return `${window.location.origin}${configuredUrl}`;
  }

  return configuredUrl;
}

export function getAuthBaseUrl(): string {
  return getOrdsBaseUrl().replace(/\/api\/v1\/?$/, '');
}
