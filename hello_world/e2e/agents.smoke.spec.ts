import { expect, test } from '@playwright/test';

// My agents in a real browser (spec-patch-15 section 4.6), run by bin/run-agent-tests.sh with a
// short-lived token for USER1. Makes an agent, makes a key and sees it exactly once, revokes the
// key and retires the agent. Skipped when its environment is absent, so bin/run-browser-smoke.sh
// still runs on its own.

const env = (n: string) => process.env[n] ?? '';
const ready = Boolean(env('ROAD_APP_URL') && env('TOKEN_USER1'));

test.describe('My agents', () => {
  test.skip(!ready, 'agent test environment not set');

  test('make an agent and a key, see the key once, revoke it, retire the agent', async ({ page }) => {
    page.on('dialog', (d) => void d.accept());
    await page.addInitScript((t) => window.sessionStorage.setItem('auth_token', t), env('TOKEN_USER1'));
    await page.goto(new URL('agents', env('ROAD_APP_URL').replace(/\/?$/, '/')).toString());
    const name = `agent-test browser ${Date.now()}`;
    await page.getByLabel('New agent').fill(name);
    await page.getByRole('button', { name: 'Make agent' }).click();
    const card = page.locator('[data-testid^="agent-"]', { hasText: name });
    await expect(card).toBeVisible();

    await card.getByLabel(`Key name for ${name}`).fill('the test laptop');
    await card.getByRole('button', { name: 'Make a key' }).click();
    await expect(page.getByTestId('new-key-value')).toHaveText(/^[a-z]+_[0-9a-f]{48}$/);
    await page.getByRole('button', { name: 'Done' }).click();
    await expect(page.getByTestId('new-key')).toHaveCount(0);
    await expect(card).toContainText('last used never');

    await card.getByRole('button', { name: 'Revoke' }).click();
    await expect(card).toContainText('revoked');
    await card.getByRole('button', { name: 'Retire' }).click();
    await expect(card).toContainText('retired');
  });
});
