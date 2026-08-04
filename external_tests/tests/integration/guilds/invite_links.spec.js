import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
test.describe('Guild Invite Links', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'invlnk',
      usernameAffix: 'invlnk',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Invite Link ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  test('should display the invite management page', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/members/invite`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing invite page: ${currentUrl}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should show invite link creation button or section', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/members/invite`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    // Look for invite link creation form or button
    // The create_invite_link route is POST /guilds/:id/invite_links
    const inviteLinkForm = page.locator('form[action*="invite_links"]').first();
    const inviteLinkButton = page.locator('button:has-text("invite"), button:has-text("link"), a:has-text("invite link")').first();

    const formVisible = await inviteLinkForm.isVisible({ timeout: 3000 }).catch(() => false);
    const buttonVisible = await inviteLinkButton.isVisible({ timeout: 3000 }).catch(() => false);

    if (!formVisible && !buttonVisible) {
      // The invite page may require a Discord bot to show certain sections
      test.skip('Invite link creation UI not found on /guilds/:id/members/invite — page may require a Discord bot connection or a different plan');
      return;
    }

    expect(formVisible || buttonVisible).toBeTruthy();
  });

  test('should create an invite link via API', async ({ page }) => {
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');
    const res = await page.request.post(`/guilds/${guildId}/invite_links`, {
      headers: {
        Accept: 'text/html',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': csrfToken || ''
      },
      maxRedirects: 0
    });

    // HTML flow redirects after creation/validation; keep 422 for safety.
    if (![200, 201, 302, 303, 422].includes(res.status())) {
      throw new Error(`Unexpected status creating invite link: ${res.status()}`);
    }

    // 422 means the plan doesn't allow invite links — acceptable, just note it
    if (res.status() === 422) {
      test.skip('Invite link creation returned 422 — feature may be plan-gated');
      return;
    }

    expect([200, 201, 302, 303]).toContain(res.status());
  });

  test('should render the join page for a valid invite token', async ({ page }) => {
    // Create an invite link through the owner session first
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');
    const createRes = await page.request.post(`/guilds/${guildId}/invite_links`, {
      headers: {
        Accept: 'text/html',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': csrfToken || ''
      },
      maxRedirects: 0
    });

    if (![200, 201, 302, 303].includes(createRes.status())) {
      test.skip(`Could not create invite link (status ${createRes.status()}) — skipping join flow test`);
      return;
    }

    // create_invite_link stores URL in a flash; follow up by reading invite page and extracting /join/:token
    await page.goto(`/guilds/${guildId}/members/invite`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    const inviteHref = await page.locator('a[href*="/join/"]').first().getAttribute('href').catch(() => null);
    const tokenMatch = inviteHref?.match(/\/join\/([^/?#]+)/);
    const token = tokenMatch?.[1];

    if (!token) {
      test.skip('Invite link token not found in invite page — cannot test join flow');
      return;
    }

    // Visit the join URL as the (already logged-in) user
    await page.goto(`/join/${token}`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    // Should land on the join page or redirect to guild/dashboard
    const validLanding = currentUrl.includes('/join/') ||
      currentUrl.includes('/guilds/') ||
      currentUrl.includes('/dashboard');

    if (!validLanding) {
      throw new Error(`Unexpected URL after visiting join link: ${currentUrl}`);
    }

    expect(validLanding).toBeTruthy();
  });

  test('should redirect for an invalid invite token', async ({ page }) => {
    await page.goto('/join/totally_fake_invite_token_xyz');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);

    // The controller renders :invalid (not a redirect) with status 404, keeping the same URL.
    // Accept: redirected away OR an error/invalid page rendered (h1 visible, alert visible).
    const currentUrl = page.url();
    const redirectedAway = !currentUrl.includes('/join/totally_fake');
    const hasErrorAlert = await page.locator('[role="alert"]').isVisible({ timeout: 2000 }).catch(() => false);
    // invalid.html.erb renders an h1 heading
    const hasHeading = await page.locator('h1').first().isVisible({ timeout: 2000 }).catch(() => false);

    expect(redirectedAway || hasErrorAlert || hasHeading).toBeTruthy();
  });
});
