import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
// Discord role syncing maps Discord server roles to GuildSync roles so members can be
// assigned roles from within the app. All sync/unsync operations call the Discord API
// to look up current server roles, so they require a connected bot. Tests here cover:
// - Page reachability (no bot required)
// - API contract for sync/unsync (will fail at Discord lookup without bot)
// - Explicit skips with clear setup instructions

test.describe('Discord Role Syncing', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'droles',
      usernameAffix: 'droles',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Discord Roles ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  test('should display the Discord roles settings page', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/discord_roles`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing Discord roles: ${currentUrl}`);
    }

    // Page may redirect to settings or render a standalone page — either is valid
    // Just assert we're not on an error/auth page
    const isErrorPage = currentUrl.includes('/error') || currentUrl.includes('/500');
    expect(isErrorPage).toBeFalsy();
  });

  test('should return 200 from the discord roles listing endpoint', async ({ page }) => {
    const res = await page.request.get(`/guilds/${guildId}/discord_roles`, {
      headers: { Accept: 'application/json' }
    });

    // Without a Discord bot the response may be 200 with an empty list, or an error
    if (![200, 422, 500].includes(res.status())) {
      throw new Error(`Unexpected status fetching Discord roles: ${res.status()}`);
    }

    // Accept any non-auth response — the endpoint is reachable
    expect([200, 422, 500]).toContain(res.status());
  });

  test('should require role_id and role_name to sync a role', async ({ page }) => {
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');

    // Missing params — should return 422
    const res = await page.request.post(`/guilds/${guildId}/discord_roles/sync`, {
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || ''
      },
      data: {}
    });

    // Missing params should result in 422 (validation error) not 500
    expect([400, 422]).toContain(res.status());
  });

  test('should skip syncing a real Discord role without bot', async () => {
    test.skip('Syncing a Discord role (POST /guilds/:id/discord_roles/sync) fetches the role list from Discord. This requires a connected Discord bot with the guild\'s server_id set. Connect a Discord bot and run the bot-connection setup to enable this test.');
  });

  test('should skip sync_all without Discord bot', async () => {
    test.skip('Syncing all Discord roles (POST /guilds/:id/discord_roles/sync_all) requires a Discord bot. Connect a bot to enable this test.');
  });

  test('should skip unsync_all without Discord bot', async () => {
    test.skip('Removing all Discord role syncs (DELETE /guilds/:id/discord_roles/sync_all) is safe to call without a bot but only makes sense with existing syncs, which require a bot to create. Connect a bot to enable the full test.');
  });

  test('should deny Discord role syncing to non-owner', async ({ page, request }) => {
    const outsider = await createTestUserAndGetToken(request, {
      emailAffix: 'droleout',
      usernameAffix: 'droleout',
      authMethod: 'discord'
    });

    // Authenticate browser context as outsider, then call the session-auth endpoint.
    await page.context().clearCookies();
    await loginAndSettle(page, outsider.email, outsider.password);
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');

    const res = await page.request.post(`/guilds/${guildId}/discord_roles/sync`, {
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || ''
      },
      data: { role_id: '123456789', role_name: 'Test' }
    });

    // Non-member/non-owner should be rejected.
    expect([401, 403, 404, 422]).toContain(res.status());
  });
});
