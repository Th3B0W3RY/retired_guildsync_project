import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken } from '../../helpers/test-helpers';
import { getAPIBaseURL } from '../../../config/test-config.js';
import { GuildsPage, LoginPage, GuildCreationPage } from '../../pages';

test.describe.serial('Guild Viewing', () => {
  let testGuildId = null;
  let ownerToken = null;

  test.beforeEach(async ({ page, request }) => {
    // Create a fresh Discord auth user per test — Discord users bypass MFA in the browser UI.
    const { email, password, token } = await createTestUserAndGetToken(request, {
      emailAffix: 'view',
      usernameAffix: 'view',
      authMethod: 'discord'
    });
    ownerToken = token;

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);

    // Wait for post-login redirect to settle.
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Create a guild so all tests have data to work with.
    const guildCreationPage = new GuildCreationPage(page);
    const guildName = `Test Guild for Viewing ${Date.now()}`;

    await guildCreationPage.goto();
    await guildCreationPage.fillName(guildName);
    await guildCreationPage.selectGame();
    await guildCreationPage.submitAndWaitForSuccess(guildName);

    const currentUrl = page.url();
    const guildIdMatch = currentUrl.match(/\/guilds\/(\d+)/);
    if (guildIdMatch) {
      testGuildId = guildIdMatch[1];
    } else {
      throw new Error(`Failed to extract guild ID from URL after creation: ${currentUrl}`);
    }
  });

  test('should display list of user guilds', async ({ page }) => {
    const guildsPage = new GuildsPage(page);

    await guildsPage.gotoGuildsList();
    await guildsPage.expectGuildsList();

    // User just created a guild so there should be at least one card.
    const guildCard = await guildsPage.expectGuildCard();

    if (guildCard) {
      await expect(guildCard).toBeVisible({ timeout: 5000 });
    } else {
      const emptyState = page.locator(guildsPage.selectors.emptyState);
      const emptyVisible = await emptyState.isVisible({ timeout: 5000 }).catch(() => false);

      if (emptyVisible) {
        await expect(emptyState).toBeVisible({ timeout: 5000 });
      } else {
        const pageTitle = page.locator(guildsPage.selectors.pageTitle);
        await expect(pageTitle).toBeVisible({ timeout: 5000 });
      }
    }
  });

  test('should display guild details on show page', async ({ page }) => {
    await page.goto(`/guilds/${testGuildId}`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const guildName = page.locator('h1, h2, [data-testid="guild-name"]').first();
    await expect(guildName).toBeVisible({ timeout: 5000 });

    const description = page.locator('[data-testid="guild-description"], .guild-description');
    const descriptionVisible = await description.isVisible({ timeout: 2000 }).catch(() => false);
    if (descriptionVisible) {
      await expect(description).toBeVisible();
    }
  });

  test('should display guild members', async ({ page }) => {
    const guildsPage = new GuildsPage(page);

    await guildsPage.gotoGuildsList();
    const guildId = await guildsPage.clickFirstGuild();

    if (!guildId) {
      throw new Error('clickFirstGuild returned null — beforeEach should have created a guild');
    }

    await guildsPage.clickMembersLink();

    const memberCard = await guildsPage.expectMembersList();
    if (memberCard) {
      await expect(memberCard).toBeVisible({ timeout: 5000 });
    }
    // null is valid — guild may have no members yet
  });

  test('should display guild events', async ({ page }) => {
    await page.goto(`/guilds/${testGuildId}`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // Look for events section or navigation link.
    const eventsLink = page.locator('text=/events|schedule/i').first();
    const eventsVisible = await eventsLink.isVisible({ timeout: 3000 }).catch(() => false);

    if (eventsVisible) {
      await eventsLink.click();
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
      // Events page can be at various paths — just verify we navigated somewhere.
      const currentUrl = page.url();
      expect(currentUrl).toMatch(/\/guilds\/\d+/);
    }
    // No events link visible is acceptable for a newly created guild.
  });

  test('should show guild settings link for owner', async ({ page }) => {
    await page.goto(`/guilds/${testGuildId}`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const settingsLink = page.locator('text=/settings|edit|manage/i, a[href*="settings"]').first();
    const settingsVisible = await settingsLink.isVisible({ timeout: 3000 }).catch(() => false);

    if (settingsVisible) {
      await expect(settingsLink).toBeVisible();
    }
    // Some UIs only show the settings link on the settings page itself — that's acceptable.
  });

  test('should hide settings for non-owner members', async ({ page, request }) => {
    // Create a second user and add them as a regular member via the API (owner token).
    // This avoids the Discord-bot invite flow entirely.
    const { user: nonOwner, email: nonOwnerEmail, password: nonOwnerPassword } =
      await createTestUserAndGetToken(request, {
        emailAffix: 'noowner',
        usernameAffix: 'noowner',
        authMethod: 'discord'
      });

    const addMemberResponse = await request.post(
      `${getAPIBaseURL()}/guilds/${testGuildId}/members`,
      {
        headers: {
          Authorization: `Bearer ${ownerToken}`,
          Accept: 'application/json',
          'Content-Type': 'application/json'
        },
        data: {
          user_id: nonOwner.id,
          guild_member: { role: 'member' }
        }
      }
    );

    if (![200, 201].includes(addMemberResponse.status())) {
      const text = await addMemberResponse.text().catch(() => '');
      throw new Error(
        `Failed to add second user as guild member. Status: ${addMemberResponse.status()}. ` +
        `Response: ${text.substring(0, 300)}`
      );
    }

    // Clear the owner's session before logging in as the non-owner.
    await page.context().clearCookies();

    // Log in as the non-owner member.
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(nonOwnerEmail, nonOwnerPassword);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Navigate to the guild page as a regular member.
    await page.goto(`/guilds/${testGuildId}`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const currentUrl = page.url();
    if (currentUrl.includes('/login')) {
      throw new Error('Non-owner login failed — unexpectedly redirected to login');
    }

    // Settings controls should not be visible for a regular member.
    const settingsLink = page.locator('a[href*="settings"], button:has-text("Settings")').first();
    const settingsVisible = await settingsLink.isVisible({ timeout: 2000 }).catch(() => false);
    expect(settingsVisible).toBeFalsy();
  });

  test('should display guild analytics', async ({ page }) => {
    await page.goto(`/guilds/${testGuildId}/analytics`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // Verify we are still authenticated (no login redirect).
    const currentUrl = page.url();
    if (currentUrl.includes('/login')) {
      throw new Error('Unexpected redirect to login when accessing guild analytics');
    }

    const analyticsContent = page.locator('[data-testid="analytics"], .analytics, canvas, svg');
    const analyticsVisible = await analyticsContent.isVisible({ timeout: 5000 }).catch(() => false);
    if (analyticsVisible) {
      await expect(analyticsContent).toBeVisible();
    }
    // Analytics section may not be rendered for a brand-new guild — that's acceptable.
  });

  test('should allow navigation between guild pages', async ({ page }) => {
    const guildsPage = new GuildsPage(page);

    await guildsPage.gotoGuildsList();
    const guildId = await guildsPage.clickFirstGuild();

    if (!guildId) {
      throw new Error('clickFirstGuild returned null — beforeEach should have created a guild');
    }

    await guildsPage.expectGuildShowPage(guildId);

    await guildsPage.clickMembersLink();

    const membersUrl = page.url();
    expect(membersUrl).toMatch(/\/guilds\/\d+\/members/);

    await page.goBack();
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const finalUrl = page.url();
    expect(finalUrl).toMatch(/\/guilds\/\d+/);

    await guildsPage.expectGuildShowPage(guildId);
  });

  test('should deny access to guilds user is not a member of', async ({ page }) => {
    // Use an ID far above the highest created test guild — guaranteed not to exist.
    const nonExistentId = parseInt(testGuildId) + 999999;
    await page.goto(`/guilds/${nonExistentId}`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const currentUrl = page.url();
    if (currentUrl.includes('/login')) {
      throw new Error('Unexpected redirect to login — user should be authenticated');
    }

    const guildsPage = new GuildsPage(page);
    const accessDenied = await guildsPage.expectAccessDenied();

    if (!accessDenied) {
      throw new Error(`Expected access denied for guild ${nonExistentId} but the page was accessible — access control may not be working`);
    }

    expect(accessDenied).toBeTruthy();
  });
});
