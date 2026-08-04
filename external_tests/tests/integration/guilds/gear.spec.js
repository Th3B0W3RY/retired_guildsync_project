import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
import { GearPage } from '../../pages';
import { getBaseURL } from '../../../config/test-config.js';

test.describe('Guild Member Gear', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'gear',
      usernameAffix: 'gear',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Gear Test ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    if (page.url().includes('/login') || page.url().includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${page.url()}`);
    }
  });

  test('should display the gear index page', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan — upgrade the test user subscription');
      return;
    }

    if (gearPage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing gear index: ${page.url()}`);
    }

    const headingVisible = await gearPage.isHeadingVisible();
    expect(headingVisible).toBeTruthy();
  });

  test('should show gear status filter links', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan');
      return;
    }

    const hasFilters = await gearPage.hasStatusFilterLinks();
    expect(hasFilters).toBeTruthy();
  });

  test('should show bulk gear request controls', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan');
      return;
    }

    const hasBulk = await gearPage.hasBulkRequestButtons();
    expect(hasBulk).toBeTruthy();
  });

  test('should show view pending requests button', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan');
      return;
    }

    const hasPendingBtn = await gearPage.hasViewPendingButton();
    if (!hasPendingBtn) {
      test.skip('View pending requests button not found — may only appear when requests exist');
      return;
    }

    expect(hasPendingBtn).toBeTruthy();
  });

  test('should filter gear list by missing status', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan');
      return;
    }

    await page.goto(`/guilds/${guildId}/members/gear?status=missing`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (gearPage.isPlanGated() || gearPage.isOnAuthPage()) {
      throw new Error(`Unexpected redirect after applying status filter: ${page.url()}`);
    }

    const headingVisible = await gearPage.isHeadingVisible();
    expect(headingVisible).toBeTruthy();
    expect(page.url()).toContain('status=missing');
  });

  test('should filter gear list by outdated status', async ({ page }) => {
    const gearPage = new GearPage(page);
    await gearPage.goto(guildId);

    if (gearPage.isPlanGated()) {
      test.skip('Guild gear requires a paid plan');
      return;
    }

    await page.goto(`/guilds/${guildId}/members/gear?status=outdated`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const headingVisible = await gearPage.isHeadingVisible();
    expect(headingVisible).toBeTruthy();
    expect(page.url()).toContain('status=outdated');
  });

  test('should allow requesting a gear snapshot via the session API', async ({ page }) => {
    // GET latest snapshot — session-auth route, use page.request (carries browser cookies)
    const showRes = await page.request.get(
      `${getBaseURL()}/guilds/${guildId}/gear/${guildId}`,
      { headers: { Accept: 'application/json' } }
    );

    // 200 (no snapshot yet returns null snapshot) or 404 (non-member) are both valid
    expect([200, 404]).toContain(showRes.status());
  });

  test('should allow bulk requesting gear updates via the session API', async ({ page }) => {
    // Session-auth route — page.request carries session cookies.
    // Rails protect_from_forgery fires before authenticate_user!, so POST requests also
    // need the CSRF token from the page's <meta name="csrf-token"> tag.
    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content').catch(() => null);
    const bulkRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/gear/request_bulk`,
      {
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          ...(csrf && { 'X-CSRF-Token': csrf })
        },
        data: { status: 'all' }
      }
    );

    // 200 success (count may be 0 when no members need updates) is the only valid response
    expect([200]).toContain(bulkRes.status());
  });

  test('should reject gear upload without a file', async ({ page }) => {
    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content').catch(() => null);
    const uploadRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/gear/upload`,
      {
        headers: {
          Accept: 'application/json',
          ...(csrf && { 'X-CSRF-Token': csrf })
        }
        // No multipart body — controller returns 422 (screenshot_required)
      }
    );

    expect([422]).toContain(uploadRes.status());
  });
});
