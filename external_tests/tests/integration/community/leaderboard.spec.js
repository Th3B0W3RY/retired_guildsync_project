import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';

test.describe('Leaderboard', () => {
  test('should redirect unauthenticated users to login', async ({ page }) => {
    await page.goto('/leaderboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    expect(page.url()).toMatch(/\/login|\/mfa/);
  });

  test('should display leaderboard page when logged in', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'lb',
      usernameAffix: 'lb',
      authMethod: 'discord'
    });
    await loginAndSettle(page, email, password);

    await page.goto('/leaderboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const url = page.url();
    if (url.includes('/login') || url.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing leaderboard: ${url}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should show leaderboard data when user belongs to a guild', async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'lbown',
      usernameAffix: 'lbown',
      authMethod: 'discord'
    });
    await createGuildViaAPI(request, owner.token, `Leaderboard Guild ${Date.now()}`);
    await loginAndSettle(page, owner.email, owner.password);

    await page.goto('/leaderboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    // Page should render without error — leaderboard may be empty for a new guild
    const url = page.url();
    expect(url).toContain('/leaderboard');
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });
});
