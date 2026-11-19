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
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
});

test('browser login reaches the protected session page', async ({ page }) => {
  const appUrl = requiredEnv('ROAD_APP_URL');
  const username = requiredEnv('ROAD_TEST_USERNAME');
  const password = requiredEnv('ROAD_TEST_PASSWORD');

  await page.goto(buildUrl(appUrl, 'login'));
  await page.getByLabel('User name').fill(username);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();

  // After sign-in the person lands on Home (spec-patch-18 7.1), and finds the session facts in the
  // account menu, in the session drawer.
  await expect(page).toHaveURL(/\/ui\/[^/]+\/?$/);
  await expect(page.getByRole('heading', { level: 1 })).toContainText(/Good (morning|afternoon|evening)/);
  await page.getByRole('button', { name: /Account menu/ }).click();
  await page.getByRole('menuitem', { name: 'Session details' }).click();
  const drawer = page.getByRole('dialog', { name: 'Session details' });
  await expect(drawer.locator('dt', { hasText: 'Principal' }).locator('xpath=following-sibling::dd')).toContainText(username);
  await expect(drawer.locator('dt', { hasText: 'Current user' }).locator('xpath=following-sibling::dd')).toContainText(username);

  const token = await page.evaluate(() => window.sessionStorage.getItem('auth_token'));
  expect(token).toBeTruthy();
});
