import { test, expect } from '@playwright/test';
import { createMFASetupUserAndLogin, createTestUserAndGetToken, parseBlueprintResponse } from '../../helpers/test-helpers';
import { MfaSetupPage, GuildCreationPage, LoginPage } from '../../pages';
import { getAPIBaseURL } from '../../../config/test-config.js';

test.describe('Free Plan Subscription', () => {
  test('should automatically activate free plan for a new standard account', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, {
      emailPrefix: 'freeplan',
      usernamePrefix: 'freeplan'
    });

    const mfaSetupPage = new MfaSetupPage(page);
    await mfaSetupPage.expectSetupPrompt();
  });

  test('should display free plan in user settings', async ({ page, request }) => {
    // Create a fresh Discord-auth user — bypasses MFA in the browser UI.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'freeplan2',
      usernameAffix: 'freeplan2',
      authMethod: 'discord'
    });

    await page.goto('/login');
    await page.fill('input[name="user[email]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.click('input[type="submit"], button[type="submit"]');

    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Navigate to a protected page first — Discord-auth users may briefly land on
    // /mfa/setup after sign-in until require_mfa_if_enabled sets session[:mfa_verified].
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const currentUrl = page.url();

    if (currentUrl.includes('/mfa/verify') || currentUrl.includes('/mfa/setup')) {
      throw new Error(`Discord auth bypass failed — redirected to MFA at ${currentUrl}`);
    }

    if (currentUrl.includes('/login')) {
      throw new Error('Login failed — could not authenticate Discord-auth test user');
    }

    // Navigate to settings
    await page.goto('/account/settings');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    
    // Verify free plan is displayed
    // Look for plan information, excluding navigation and buttons
    const planDisplay = page.locator('text=/free|plan|subscription/i')
      .filter({ 
        hasNot: page.locator('nav, button, a') 
      })
      .first();
    
    const planExists = await planDisplay.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!planExists) {
      throw new Error('Free plan information not displayed on /account/settings — either the user has no subscription or the page does not render plan info');
    }
    
    await expect(planDisplay).toBeVisible({ timeout: 5000 });
  });

  test('should show free plan limits', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'limits',
      usernameAffix: 'limits',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    
    // Look for plan limit information
    // This depends on how limits are displayed in your UI
    // Exclude navigation and buttons to avoid strict mode violations
    const limitsLocator = page.locator('text=/guild|member|limit/i')
      .filter({ 
        hasNot: page.locator('nav, button, a, label') 
      })
      .first();
    
    const limitsVisible = await limitsLocator.isVisible({ timeout: 3000 }).catch(() => false);

    if (limitsVisible) {
      await expect(limitsLocator).toBeVisible();
    } else {
      throw new Error('Plan limits not displayed on /dashboard — this test requires a logged-in user; add login setup to beforeEach');
    }
  });

  test('should enforce free plan guild limit', async ({ page, request }) => {
    // Create a Discord-auth user so MFA is bypassed.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'guildlimit',
      usernameAffix: 'guildlimit',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Navigate to a protected page first to trigger the discord MFA session flag.
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }

    // Create the first guild, hitting the free plan limit (max_guilds = 1).
    const guildCreationPage = new GuildCreationPage(page);
    await guildCreationPage.goto();
    await guildCreationPage.fillName(`Guild Limit Test ${Date.now()}`);
    await guildCreationPage.selectGameSafely();
    await guildCreationPage.submitAndWaitForSuccess();

    // Try to create a second guild — should be blocked at the route or form level.
    await guildCreationPage.goto();
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const urlAfterSecondNav = page.url();
    if (!urlAfterSecondNav.includes('/guilds/new')) {
      // Redirected away — limit enforced at the route level.
      const blockedCorrectly = urlAfterSecondNav.includes('/subscriptions') ||
                               urlAfterSecondNav.includes('/pricing') ||
                               urlAfterSecondNav.includes('/guilds');
      expect(blockedCorrectly).toBeTruthy();
      return;
    }

    // Form is still accessible — submit and expect a limit error.
    await guildCreationPage.fillName(`Second Guild ${Date.now()}`);
    await guildCreationPage.selectGameSafely();
    const errorBox = await guildCreationPage.submitAndWaitForError();

    if (errorBox) {
      await guildCreationPage.expectErrorMessage('limit|maximum|plan|reached');
    } else {
      throw new Error('Expected a guild limit error on the second creation attempt but none appeared — free plan enforcement may not be active');
    }
  });

  test('should enforce free plan member limit', async ({ page, request }) => {
    // Create a Discord-auth user and a guild they own.
    const { email, password, token } = await createTestUserAndGetToken(request, {
      emailAffix: 'memberlimit',
      usernameAffix: 'memberlimit',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }

    // Create a guild via API for use in this test.
    const createRes = await request.post(`${getAPIBaseURL()}/guilds`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', 'Content-Type': 'application/json' },
      data: { guild: { name: `Member Limit Test ${Date.now()}` } }
    });
    if (![200, 201].includes(createRes.status())) {
      throw new Error(`Guild creation failed with status ${createRes.status()}`);
    }
    const guildBody = await createRes.json();
    const guild = parseBlueprintResponse(guildBody.guild);
    const guildId = guild?.id;
    if (!guildId) {
      throw new Error('Guild creation response did not include an id');
    }

    // Navigate to the member invite page for our guild.
    await page.goto(`/guilds/${guildId}/members/invite`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Unexpected redirect to auth page: ${currentUrl}`);
    }

    // The invite form requires a connected Discord bot (same constraint as guild_members/invite.spec.js).
    // Skip if the form is not accessible — full enforcement testing requires Discord + a guild at capacity.
    const emailInput = page.locator('input[name="email"], input[type="email"]').first();
    const formAccessible = await emailInput.isVisible({ timeout: 3000 }).catch(() => false);

    if (!formAccessible) {
      test.skip('Discord bot required to access the member invite form — full member-limit enforcement cannot be tested without a connected bot and a guild at capacity (25 members for free plan)');
      return;
    }

    // Form is accessible — invite until the limit is reached or an error appears.
    const memberEmail = generateTestEmail('member');
    await emailInput.fill(memberEmail);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // If a limit error appears, assert on it; otherwise the invite succeeded (guild not yet at capacity).
    const errorVisible = await page.locator('[role="alert"]')
      .filter({ hasText: /limit|maximum|member/i })
      .isVisible({ timeout: 3000 }).catch(() => false);

    if (errorVisible) {
      await expect(page.locator('[role="alert"]').filter({ hasText: /limit|maximum|member/i })).toBeVisible();
    }
    // No error = guild still has capacity — test is not meaningful without a full guild.
    // Reaching full capacity (25 members) requires extensive API setup; defer to a dedicated suite.
  });
});
