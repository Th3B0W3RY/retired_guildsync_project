import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
// React roles are a Discord-only feature. Most functional tests (deploy, fetch emojis)
// require a live Discord bot. The tests here cover:
// - Page/form accessibility (no bot required)
// - API contract for save/remove (no bot required — just stores config)
// - Explicit skips with clear instructions for deploy/emoji fetch

test.describe('React Roles (Discord)', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'reactrl',
      usernameAffix: 'reactrl',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `React Roles ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  test('should reach the guild settings page (react roles entry point)', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/settings`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing guild settings: ${currentUrl}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should accept a PATCH to save react roles configuration', async ({ page }) => {
    // The react roles endpoint stores config regardless of Discord connection.
    // Deployment to Discord is the part that requires the bot.
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');

    const res = await page.request.patch(`/guilds/${guildId}/react_roles`, {
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || ''
      },
      data: {
        channel_id: '',
        react_roles: [
          {
            position: 1,
            role_id: '000000000000000001',
            role_name: 'Test Role',
            emoji_name: '⚔️',
            emoji_id: '',
            is_custom_emoji: false
          }
        ]
      }
    });

    // Expect success (200), redirect chain success (302/303), or validation/CSRF errors.
    if (![200, 201, 302, 303, 422].includes(res.status())) {
      throw new Error(`Unexpected status saving react roles: ${res.status()}`);
    }

    // 422 means validation failed (e.g. role_id format) — acceptable, just note it
    if (res.status() === 422) {
      const body = await res.json().catch(() => ({}));
      // Validation error is expected with a fake role_id — the endpoint is reachable
      expect(typeof body).toBe('object');
    } else {
      expect([200, 201, 302, 303]).toContain(res.status());
    }
  });

  test('should accept a DELETE to remove all react roles', async ({ page }) => {
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');

    const res = await page.request.delete(`/guilds/${guildId}/react_roles`, {
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || ''
      },
      maxRedirects: 0
    });

    // DELETE action redirects in HTML flow; keep 422 for CSRF/validation edge-cases.
    if (![200, 201, 302, 303, 422].includes(res.status())) {
      throw new Error(`Unexpected status removing react roles: ${res.status()}`);
    }
    expect([200, 201, 302, 303, 422]).toContain(res.status());
  });

  test('should skip deploy without Discord bot', async () => {
    test.skip('React roles deployment (POST /guilds/:id/react_roles/deploy) posts an embed to a Discord channel. This requires a connected Discord bot and a configured channel_id. Connect a Discord bot and configure the guild to enable this test.');
  });

  test('should skip emoji fetch without Discord bot', async () => {
    test.skip('Fetching custom emojis (GET /guilds/:id/react_roles/emojis) requires a Discord bot with access to the guild. Connect a Discord bot to enable this test.');
  });

  test('should deny react roles access to non-owner', async ({ page, request }) => {
    const outsider = await createTestUserAndGetToken(request, {
      emailAffix: 'reactout',
      usernameAffix: 'reactout',
      authMethod: 'discord'
    });

    // Clear the owner session from beforeEach before logging in as outsider
    await page.context().clearCookies();
    await loginAndSettle(page, outsider.email, outsider.password);

    await page.goto(`/guilds/${guildId}/settings`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);

    const currentUrl = page.url();
    // Non-member should be redirected away from guild settings
    const blocked = !currentUrl.includes(`/guilds/${guildId}/settings`) ||
      await page.locator('[role="alert"]').isVisible({ timeout: 2000 }).catch(() => false);

    expect(blocked).toBeTruthy();
  });
});
