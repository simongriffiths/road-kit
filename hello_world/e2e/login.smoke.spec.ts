import { expect, test } from '@playwright/test';

function requiredEnv(name: string): string {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

function buildUrl(baseUrl: string, relativePath: string): string {
  return new URL(relativePath, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`).toString();
}

test('protected route redirects to login when no token is present', async ({ page }) => {
  const appUrl = requiredEnv('ROAD_APP_URL');

  await page.goto(buildUrl(appUrl, 'session'));
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('heading', { name: 'Login' })).toBeVisible();
});

test('browser login reaches the protected session page', async ({ page }) => {
  const appUrl = requiredEnv('ROAD_APP_URL');
  const username = requiredEnv('ROAD_TEST_USERNAME');
  const password = requiredEnv('ROAD_TEST_PASSWORD');

  await page.goto(buildUrl(appUrl, 'login'));
  await page.getByLabel('Username').fill(username);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign In' }).click();

  await expect(page).toHaveURL(/\/session$/);
  await expect(page.getByRole('heading', { name: 'Protected Session' })).toBeVisible();
  await expect(page.locator('.kv div').filter({ has: page.getByText('Principal') }).locator('dd')).toHaveText(username);
  await expect(page.locator('.kv div').filter({ has: page.getByText('Current User') }).locator('dd')).toHaveText(username);

  const token = await page.evaluate(() => window.sessionStorage.getItem('auth_token'));
  expect(token).toBeTruthy();
});
