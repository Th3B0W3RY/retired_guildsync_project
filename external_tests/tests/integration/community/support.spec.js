import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle } from '../../helpers/test-helpers';
import { getBaseURL } from '../../../config/test-config.js';

test.describe('Support Pages', () => {
  test('should redirect /support/discord without authentication', async ({ request }) => {
    // Footer support links are public redirects (skip_before_action :authenticate_user!)
    const res = await request.get(`${getBaseURL()}/support/discord`, { maxRedirects: 0 });
    // Expect a redirect to the external Discord URL or a 3xx
    expect(res.status()).toBeGreaterThanOrEqual(300);
    expect(res.status()).toBeLessThan(400);
  });

  test('should redirect /support/documentation without authentication', async ({ request }) => {
    const res = await request.get(`${getBaseURL()}/support/documentation`, { maxRedirects: 0 });
    expect(res.status()).toBeGreaterThanOrEqual(300);
    expect(res.status()).toBeLessThan(400);
  });

  test('should redirect /support/contact-link without authentication', async ({ request }) => {
    const res = await request.get(`${getBaseURL()}/support/contact-link`, { maxRedirects: 0 });
    expect(res.status()).toBeGreaterThanOrEqual(300);
    expect(res.status()).toBeLessThan(400);
  });

  test('should redirect unauthenticated users to login for /support/contact', async ({ page }) => {
    await page.goto('/support/contact');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    expect(page.url()).toMatch(/\/login|\/mfa/);
  });

  test('should redirect authenticated users from /support/contact to external support system', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'sup',
      usernameAffix: 'sup',
      authMethod: 'discord'
    });
    await loginAndSettle(page, email, password);

    await page.goto('/support/contact');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const url = page.url();
    // GuildSync auth succeeds and redirects to the external support system (guildsync.raiseaticket.com).
    // That external SPA has its own auth and may land on its own /login page — this is expected current
    // behavior. Only fail if still on the GuildSync-local login/mfa page (i.e. GuildSync auth failed).
    const isLocalAuthPage = /^https?:\/\/localhost|^https?:\/\/127\.0\.0\.1/.test(url) &&
      (url.includes('/login') || url.includes('/mfa'));
    if (isLocalAuthPage) {
      throw new Error(`GuildSync auth failed — redirected to local login: ${url}`);
    }

    // Redirected away from GuildSync to external support system — correct
    expect(url).not.toContain('localhost');
  });
});
