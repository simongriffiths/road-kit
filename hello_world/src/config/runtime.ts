// The contract major version this client speaks (spec-patch-17 7.6). A later major version answers
// 400 VERSION_MISMATCH, so a copied template fails clearly instead of quietly.
export const API_VERSION = '0';

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
