import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';

// The app shell in a real browser (spec-patch-18 section 9): Home, the account menu and session
// drawer by keyboard, the theme switch, 320 pixels wide, and an accessibility scan in both themes.
// Run by bin/run-agent-tests.sh with a short-lived token for USER1. Skipped when its environment is
// absent. The todo it makes starts "agent-test", which test/agents/90_cleanup.sql removes.

const env = (n: string) => process.env[n] ?? '';
const ready = Boolean(env('ROAD_APP_URL') && env('TOKEN_USER1') && env('ORDS_BASE_URL'));
const url = (path: string) => new URL(path, env('ROAD_APP_URL').replace(/\/?$/, '/')).toString();
const PAGES = ['', 'todos', 'agents', 'session'];

async function signIn(page: Page) {
  await page.addInitScript((t) => window.sessionStorage.setItem('auth_token', t), env('TOKEN_USER1'));
}

const sideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);

test.describe('App shell', () => {
  test.skip(!ready, 'agent test environment not set');

  test('Home counts a todo due today', async ({ page }) => {
    await signIn(page);
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    const offset = -now.getTimezoneOffset();
    const due = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T00:00:00`
      + `${offset < 0 ? '-' : '+'}${pad(Math.floor(Math.abs(offset) / 60))}:${pad(Math.abs(offset) % 60)}`;
    const title = `agent-test home ${Date.now()}`;
    const made = await fetch(`${env('ORDS_BASE_URL')}/todos/`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env('TOKEN_USER1')}`, 'Content-Type': 'application/json',
        'Accept-Version': '0', 'Idempotency-Key': crypto.randomUUID()
      },
      body: JSON.stringify({ title, due_at: due })
    }).then((r) => r.json() as Promise<{ decision: string }>);
    expect(made.decision).toBe('accepted');

    await page.goto(url(''));
    await expect(page.getByRole('heading', { level: 1 })).toContainText(/Good (morning|afternoon|evening)/);
    for (const label of ['Open', 'Due today', 'Overdue']) await expect(page.getByText(label, { exact: true }).first()).toBeVisible();
    await expect(page.getByRole('region', { name: /^Due today/ })).toContainText(title);
  });

  test('keyboard: account menu, session drawer, and focus returns', async ({ page }) => {
    await signIn(page);
    await page.goto(url(''));
    const account = page.getByRole('button', { name: /Account menu/ });
    await expect(account).toBeVisible();
    for (let i = 0; i < 20 && !(await account.evaluate((el) => el === document.activeElement)); i += 1) {
      await page.keyboard.press('Tab');
    }
    await expect(account).toBeFocused();
    await page.keyboard.press('Enter');
    await page.getByRole('menuitem', { name: 'Session details' }).focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('dialog', { name: 'Session details' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog', { name: 'Session details' })).toHaveCount(0);
    await expect(account).toBeFocused();
  });

  test('theme: dark is kept across a reload, and System follows the browser', async ({ page }) => {
    await signIn(page);
    await page.emulateMedia({ colorScheme: 'light' });
    await page.goto(url(''));
    const dark = () => page.evaluate(() => document.documentElement.classList.contains('dark'));
    expect(await dark()).toBe(false);

    await page.getByRole('button', { name: /Account menu/ }).click();
    await page.getByRole('menuitemradio', { name: 'Dark' }).click();
    expect(await dark()).toBe(true);
    await page.reload();
    expect(await dark()).toBe(true);

    await page.getByRole('button', { name: /Account menu/ }).click();
    await page.getByRole('menuitemradio', { name: 'System' }).click();
    expect(await dark()).toBe(false);
    await page.emulateMedia({ colorScheme: 'dark' });
    await expect.poll(dark).toBe(true);
  });

  test('320 pixels wide: nothing scrolls sideways and the nav is in the tab bar', async ({ page }) => {
    await signIn(page);
    await page.setViewportSize({ width: 320, height: 700 });
    for (const path of PAGES) {
      await page.goto(url(path));
      await expect(page.getByRole('main')).toBeVisible();
      expect(await sideways(page), `/${path} scrolls sideways`).toBe(false);
      await expect(page.getByRole('navigation', { name: 'Main' })).toHaveCount(1);
    }
    await page.goto(url(''));
    await page.getByRole('button', { name: /Account menu/ }).click();
    await page.getByRole('menuitem', { name: 'Session details' }).click();
    await expect(page.getByRole('dialog', { name: 'Session details' })).toBeVisible();
    expect(await sideways(page), 'the drawer scrolls sideways').toBe(false);
  });

  for (const scheme of ['light', 'dark'] as const) {
    test(`accessibility scan, ${scheme} theme`, async ({ page }) => {
      await signIn(page);
      await page.emulateMedia({ colorScheme: scheme });
      for (const path of PAGES) {
        await page.goto(url(path));
        await expect(page.getByRole('main')).toBeVisible();
        await page.waitForTimeout(500);
        const result = await new AxeBuilder({ page }).analyze();
        const bad = result.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
        expect(bad.map((v) => `${path || 'home'}: ${v.id}`), `/${path}`).toEqual([]);
      }
      await page.goto(url(''));
      await page.getByRole('button', { name: /Account menu/ }).click();
      await page.getByRole('menuitem', { name: 'Session details' }).click();
      await page.waitForTimeout(500);
      const drawer = (await new AxeBuilder({ page }).analyze()).violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
      expect(drawer.map((v) => `drawer: ${v.id}`)).toEqual([]);
    });
  }

  test('sign-in: 320 pixels wide, no sideways scroll', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 700 });
    await page.goto(url('login'));
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
    expect(await sideways(page)).toBe(false);
    const bad = (await new AxeBuilder({ page }).analyze()).violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    expect(bad.map((v) => v.id)).toEqual([]);
  });
});
