import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken } from '../../helpers/test-helpers';
import { LoginPage, GuildCreationPage } from '../../pages';
import { isDiscordBotConnected } from '../../helpers/discord-helpers';

/**
 * Discord Bot Connection Tests
 *
 * NOTE: Discord bot connection requires OAuth flow which cannot be fully automated
 * due to CAPTCHA requirements. These tests verify:
 * 1. Discord connection UI elements exist
 * 2. Features work when Discord is already connected (via test mode or manual setup)
 *
 * For full bot connection testing, backend must implement test mode bypass
 * (see DISCORD_OAUTH_TESTING_RECOMMENDATIONS.md).
 */
test.describe('Discord Bot Connection', () => {
  let testGuildId = null;

  test.beforeEach(async ({ page, request }) => {
    // Create a fresh Discord auth user — bypasses MFA in the browser UI.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'discord',
      usernameAffix: 'discord',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);

    // Wait for redirect; Discord users may briefly land on /mfa/setup — navigating to
    // any protected page resolves this via require_mfa_if_enabled.
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Create a guild for Discord connection testing
    const guildCreationPage = new GuildCreationPage(page);
    const guildName = `Test Guild for Discord ${Date.now()}`;

    await guildCreationPage.goto();
    await guildCreationPage.fillName(guildName);
    await guildCreationPage.selectGame();
    await guildCreationPage.submitAndWaitForSuccess(guildName);

    const currentUrl = page.url();
    const guildIdMatch = currentUrl.match(/\/guilds\/(\d+)/);
    if (guildIdMatch) {
      testGuildId = guildIdMatch[1];
    } else {
      throw new Error(`Failed to extract guild ID from URL: ${currentUrl}`);
    }

  });

  test('should display Discord connection UI when bot is not connected', async ({ page }) => {
    // Navigate to event creation page - should show Discord warning
    await page.goto(`/guilds/${testGuildId}/events/schedule`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);
    
    // Check for Discord warning (bot not connected)
    const warning = page.locator('text=Bot Not Connected, div:has-text("Bot Not Connected")');
    const warningVisible = await warning.isVisible({ timeout: 5000 }).catch(() => false);
    
    // Should show warning if bot is not connected
    const isConnected = await isDiscordBotConnected(page, testGuildId);
    if (!isConnected) {
      expect(warningVisible).toBeTruthy();
      
      // Check for connect button
      const connectButton = page.locator(
        'button:has-text("Connect Bot"), ' +
        'a:has-text("Connect Bot"), ' +
        'button:has-text("Connect Bot To Guild Discord")'
      ).first();
      const buttonVisible = await connectButton.isVisible({ timeout: 3000 }).catch(() => false);
      expect(buttonVisible).toBeTruthy();
    } else {
      // Bot is already connected (via test mode or manual setup)
      expect(warningVisible).toBeFalsy();
    }
  });
});
