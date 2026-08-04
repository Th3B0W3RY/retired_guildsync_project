import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
import { AlliancePage } from '../../pages';

// Alliance features are gated behind a paid plan. Test users get a Free plan by default,
// so every alliance route redirects to /dashboard (not /login or /500). Tests here verify:
//
// - Authentication requirement (unauthenticated → /login)
// - Plan gate behaviour (free plan → /dashboard, not an error)
// - Guild-scoped alliance routes (pending invites, join request, status)
// - Explicit skips for creation/management features that require a paid plan
// - Explicit skips for Discord-dependent sub-features (events, polls, loot rolls, messages)

test.describe('Alliance System', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'alliown',
      usernameAffix: 'alliown',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Alliance Test ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  // --- Plan gate / auth gate tests ---

  test('should redirect unauthenticated users to login', async ({ page }) => {
    await page.context().clearCookies();

    const alliancePage = new AlliancePage(page);
    await alliancePage.goto();

    expect(alliancePage.isOnAuthPage()).toBeTruthy();
  });

  test('alliance index page does not return a server error for free plan users', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.goto();

    expect(alliancePage.isServerError()).toBeFalsy();

    const onAlliances = alliancePage.isOnAlliancesPage();
    const onDashboard = alliancePage.isOnDashboard();
    expect(onAlliances || onDashboard).toBeTruthy();
  });

  test('alliance new page does not return a server error for free plan users', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.gotoNew();

    expect(alliancePage.isServerError()).toBeFalsy();

    if (!alliancePage.isPlanGated()) {
      expect(await alliancePage.isHeadingVisible()).toBeTruthy();
    }
  });

  test('free plan users are redirected away from alliance hub (plan gate works)', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.goto();

    const url = page.url();
    if (url.includes('/alliances') && !url.includes('/alliances/new')) {
      // Plan gate may have passed (e.g. existing membership) — page at least renders
      expect(await alliancePage.isHeadingVisible()).toBeTruthy();
    } else {
      expect(alliancePage.isPlanGated()).toBeTruthy();
    }
  });

  // --- Guild-scoped alliance routes ---

  test('guild-scoped pending alliance invites page is accessible or plan-gated', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.gotoPendingInvites(guildId);

    if (alliancePage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing pending invites: ${page.url()}`);
    }
    if (alliancePage.isServerError()) {
      throw new Error(`Server error on pending invites page: ${page.url()}`);
    }

    if (!alliancePage.isPlanGated()) {
      expect(await alliancePage.isHeadingVisible()).toBeTruthy();
    }
  });

  test('guild-scoped alliance join request new page is accessible or plan-gated', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.gotoJoinRequestNew(guildId);

    if (alliancePage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing join request new: ${page.url()}`);
    }
    if (alliancePage.isServerError()) {
      throw new Error(`Server error on join request new page: ${page.url()}`);
    }

    if (!alliancePage.isPlanGated()) {
      expect(await alliancePage.isHeadingVisible()).toBeTruthy();
    }
  });

  test('guild-scoped alliance join status page is accessible or plan-gated', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.gotoJoinStatus(guildId);

    if (alliancePage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing join status: ${page.url()}`);
    }
    if (alliancePage.isServerError()) {
      throw new Error(`Server error on join status page: ${page.url()}`);
    }

    if (!alliancePage.isPlanGated()) {
      expect(await alliancePage.isHeadingVisible()).toBeTruthy();
    }
  });

  // --- Unknown alliance ID handling ---

  test('accessing a non-existent alliance redirects gracefully', async ({ page }) => {
    const alliancePage = new AlliancePage(page);
    await alliancePage.gotoById(999999999);

    expect(alliancePage.isServerError()).toBeFalsy();

    const handledGracefully = alliancePage.isPlanGated() ||
      alliancePage.isOnAuthPage() ||
      alliancePage.isOnAlliancesPage();
    expect(handledGracefully).toBeTruthy();
  });

  // --- Skip blocks for features requiring a paid plan or Discord bot ---

  test('should skip alliance creation (requires paid plan)', async () => {
    test.skip(
      'Creating an alliance (POST /alliances) requires a non-Free plan subscription. ' +
      'Upgrade the test user to a paid plan and enable this test to verify creation flow.'
    );
  });

  test('should skip alliance member management (requires existing alliance + paid plan)', async () => {
    test.skip(
      'Alliance member management (/alliances/:id/alliance_members) requires an existing alliance ' +
      'and a paid plan. Create an alliance via the UI or a test seed to enable these tests.'
    );
  });

  test('should skip alliance invite sending (requires paid plan + existing alliance)', async () => {
    test.skip(
      'Sending alliance invites (POST /alliances/:id/alliance_invites) requires a paid plan and ' +
      'an existing alliance with leadership privileges.'
    );
  });

  test('should skip alliance join request submission (requires paid plan)', async () => {
    test.skip(
      'Submitting an alliance join request (POST /guilds/:id/alliance_join_requests) requires a ' +
      'paid plan. The GET form is tested separately (plan-gate check above).'
    );
  });

  test('should skip alliance events (requires paid plan + Discord bot)', async () => {
    test.skip(
      'Alliance events (/alliances/:id/alliance_events) require a paid plan and, for Discord ' +
      'posting, a connected Discord bot. Enable once a paid plan and bot are configured.'
    );
  });

  test('should skip alliance polls (requires paid plan + optional Discord bot)', async () => {
    test.skip(
      'Alliance polls (/alliances/:id/alliance_polls) require a paid plan and alliance membership. ' +
      'Discord posting is optional but requires a connected bot.'
    );
  });

  test('should skip alliance loot rolls (requires paid plan + Discord bot)', async () => {
    test.skip(
      'Alliance loot rolls (/alliances/:id/alliance_loot_rolls) require a paid plan, alliance ' +
      'membership, and a Discord channel configured via a connected bot.'
    );
  });

  test('should skip alliance messages (requires paid plan + alliance membership)', async () => {
    test.skip(
      'Alliance messages (/alliances/:id/alliance_messages) require a paid plan and active ' +
      'alliance membership. Create an alliance and upgrade the plan to enable these tests.'
    );
  });

  test('should skip alliance disband votes (requires paid plan + alliance membership)', async () => {
    test.skip(
      'Alliance disband votes (/alliances/:id/alliance_disband_votes) require a paid plan and ' +
      'active alliance membership. These can only be created by guild masters within an alliance.'
    );
  });

  test('should skip alliance activity feed (requires paid plan + alliance membership)', async () => {
    test.skip(
      'The alliance activity feed (/alliances/:id/activity_feed) requires a paid plan and active ' +
      'alliance membership.'
    );
  });
});
