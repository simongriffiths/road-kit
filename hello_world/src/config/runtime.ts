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
