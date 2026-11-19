import { expect, test } from '@playwright/test';

// Todos in a real browser (spec-patch-17 section 5), run by bin/run-agent-tests.sh with a short-lived
// token for USER1. Titles start "agent-test", which test/agents/90_cleanup.sql removes. Skipped when
// its environment is absent, so bin/run-browser-smoke.sh still runs on its own.

const env = (n: string) => process.env[n] ?? '';
const ready = Boolean(env('ROAD_APP_URL') && env('TOKEN_USER1') && env('ORDS_BASE_URL'));

const api = (path: string, init: RequestInit = {}) =>
  fetch(`${env('ORDS_BASE_URL')}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${env('TOKEN_USER1')}`, 'Content-Type': 'application/json', 'Accept-Version': '0' }
  }).then((r) => r.json() as Promise<Record<string, any>>);

test.describe('Todos', () => {
  test.skip(!ready, 'agent test environment not set');

  test('add, refuse a repeat, edit, meet a stale token, complete, reopen, delete, keyboard, 320 pixels', async ({ page }) => {
    page.on('dialog', (d) => void d.accept());
    const badRequests: string[] = [];
    page.on('response', (r) => { if (r.status() === 400) badRequests.push(`${r.request().method()} ${r.url()}`); });

    await page.addInitScript((t) => window.sessionStorage.setItem('auth_token', t), env('TOKEN_USER1'));
    await page.goto(new URL('todos', env('ROAD_APP_URL').replace(/\/?$/, '/')).toString());

    const stamp = Date.now();
    const title = `agent-test todo ${stamp}`;
    const add = async (t: string) => {
      await page.locator('#add-title').fill(t);
      await page.getByRole('button', { name: 'Add todo' }).click();
    };
    const row = (t: string) => page.locator('[data-testid^="todo-"]', { hasText: t });

    // 1. Add, and see it in Open.
    await add(title);
    await expect(row(title)).toHaveCount(1);
    await expect(page.locator('#add-title')).toHaveValue('');

    // 2. The same title again is refused with the database's words; one copy remains.
    await add(title);
    await expect(page.getByRole('status')).toContainText(/already|title/i);
    await expect(row(title)).toHaveCount(1);

    // 3. Edit the title.
    const revised = `${title} revised`;
    await row(title).getByRole('button', { name: 'Edit' }).click();
    await page.getByLabel('Title', { exact: true }).nth(1).fill(revised);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(row(revised)).toHaveCount(1);
    await expect(page.getByRole('status')).toHaveCount(0);

    // 4. Someone else changes it while the form is open: stale-token notice, text kept, second save accepted.
    const found = await api(`/todos/?status=OPEN&query=${stamp}`);
    const id = found.items[0].todo_id as number;
    await row(revised).getByRole('button', { name: 'Edit' }).click();
    const mine = `${title} mine`;
    await page.getByLabel('Title', { exact: true }).nth(1).fill(mine);
    const fresh = await api(`/todos/${id}/`);
    const other = await api(`/todos/${id}/revisions/`, {
      method: 'POST',
      body: JSON.stringify({ read_token: fresh.read_token, notes: 'changed elsewhere' })
    });
    expect(other.decision).toBe('accepted');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('status')).toContainText('Someone changed this todo while you were looking');
    await expect(page.getByLabel('Title', { exact: true }).nth(1)).toHaveValue(mine);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(row(mine)).toHaveCount(1);
    await expect(page.getByRole('status')).toHaveCount(0);

    // 5. Done, found in Done, reopen.
    await row(mine).getByRole('button', { name: 'Done' }).click();
    await expect(row(mine)).toHaveCount(0);
    await page.getByRole('button', { name: 'Done', exact: true }).first().click();
    await expect(row(mine)).toHaveCount(1);
    await row(mine).getByRole('button', { name: 'Reopen' }).click();
    await expect(row(mine)).toHaveCount(0);
    await page.getByRole('button', { name: 'Open', exact: true }).click();
    await expect(row(mine)).toHaveCount(1);

    // 6. Delete; gone from both tabs.
    await row(mine).getByRole('button', { name: 'Delete' }).click();
    await expect(row(mine)).toHaveCount(0);
    await page.getByRole('button', { name: 'Done', exact: true }).first().click();
    await expect(row(mine)).toHaveCount(0);
    await page.getByRole('button', { name: 'Open', exact: true }).click();

    // 7. Add using only the keyboard.
    const keyed = `agent-test keyboard ${stamp}`;
    await page.locator('#add-title').focus();
    await page.keyboard.type(keyed);
    // Tab through notes and the date input (which has a stop each for day, month and year) to the button.
    const addButton = page.getByRole('button', { name: 'Add todo' });
    for (let i = 0; i < 8 && !(await addButton.evaluate((el) => el === document.activeElement)); i += 1) {
      await page.keyboard.press('Tab');
    }
    await expect(page.getByRole('button', { name: 'Add todo' })).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(row(keyed)).toHaveCount(1);

    // 8. At 320 pixels the page does not scroll sideways.
    await page.setViewportSize({ width: 320, height: 700 });
    const wide = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    expect(wide).toBe(false);

    expect(badRequests, 'the page made a wrong call').toEqual([]);
  });
});
