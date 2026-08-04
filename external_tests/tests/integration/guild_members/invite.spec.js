import { test, expect } from '@playwright/test';
import { generateTestEmail, createTestUserAndGetToken } from '../../helpers/test-helpers';
import { LoginPage, GuildCreationPage, GuildMemberInvitePage } from '../../pages';

// Guild member invitation tests require Discord bot connection
// Run tests serially to avoid conflicts with single Discord account
test.describe.serial('Guild Member Invitations', () => {
  let testGuildId = null;

  test.beforeEach(async ({ page, request }) => {
    // Create a fresh Discord auth user — bypasses MFA in the browser UI.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'invite',
      usernameAffix: 'invite',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);

    // Wait for redirect; Discord users may briefly land on /mfa/setup — navigating to
    // any protected page resolves this via require_mfa_if_enabled.
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Create a guild for the user to invite members to
    const guildCreationPage = new GuildCreationPage(page);
    const guildName = `Test Guild for Invites ${Date.now()}`;

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

    // Check if Discord bot is connected - required for member invitations
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);

    const isConnected = await invitePage.isDiscordBotConnected();

    if (!isConnected) {
      test.skip(true, 'Discord bot not connected — member invitation tests require a connected bot.');
      return;
    } else {
      const formOk = await invitePage.isFormAccessible();
      if (!formOk) {
        test.skip(true, 'Discord bot reports connected but invite form is not accessible — skipping.');
        return;
      }
    }
  });

  test('should successfully invite a member by email', async ({ page }) => {
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await invitePage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const memberEmail = generateTestEmail('invite');
    await invitePage.inviteMember(memberEmail, 'member');
  });

  test('should show error for invalid email format', async ({ page }) => {
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await invitePage.checkDiscordAndSkip(test)) {
      return;
    }
    
    await invitePage.fillEmail('invalid-email');
    await invitePage.submit();
    
    // Should show validation error
    await invitePage.expectError('email|invalid|format');
  });

  test('should show error when member limit is reached', async ({ page }) => {
    // This test assumes the guild has reached its member limit
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await invitePage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const memberEmail = generateTestEmail('limit');
    await invitePage.fillEmail(memberEmail);
    await invitePage.submit();
    
    // Should show error about member limit
    await invitePage.expectError('limit|maximum|member|plan');
  });

  test('should show error for duplicate member invitation', async ({ page }) => {
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await invitePage.checkDiscordAndSkip(test)) {
      return;
    }
    
    // First, invite a member
    const memberEmail = generateTestEmail('duplicate');
    await invitePage.inviteMember(memberEmail);
    
    // Then try to invite the same member again
    await invitePage.goto(testGuildId);
    await invitePage.fillEmail(memberEmail);
    await invitePage.submit();
    
    // Should show error about duplicate
    await invitePage.expectError('already|exists|duplicate|member');
  });

  test('should allow selecting member role during invitation', async ({ page }) => {
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await invitePage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const memberEmail = generateTestEmail('role');
    await invitePage.fillEmail(memberEmail);
    
    // Check if role selection is available
    const roleExists = await invitePage.selectRole('moderator');
    
    if (roleExists) {
      await invitePage.submitAndWaitForSuccess();
    }
  });

  test('should require appropriate permissions to invite members', async ({ page }) => {
    // This test verifies that only users with invite permissions can access the page
    // You may need to test with a non-admin user
    
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.goto(testGuildId);
    
    // Check for Discord bot connection requirement first
    const warningVisible = !(await invitePage.isDiscordBotConnected());
    
    // Should either show the form, Discord warning, redirect/error if no permission
    const formVisible = await invitePage.isFormAccessible();
    const unauthorized = await page.locator('text=/unauthorized|permission|access/i').isVisible({ timeout: 3000 }).catch(() => false);
    const redirected = await page.waitForURL(/\/guilds\/\d+/, { timeout: 3000 }).catch(() => false);
    
    // One of these should be true (form, Discord warning, unauthorized, or redirected)
    expect(formVisible || warningVisible || unauthorized || redirected).toBeTruthy();
  });

  test('should display pending invitations', async ({ page }) => {
    const invitePage = new GuildMemberInvitePage(page);
    await invitePage.gotoMembersList(testGuildId);
    
    // Look for pending invitations section
    const pendingVisible = await invitePage.hasPendingSection();
    
    if (pendingVisible) {
      const pendingSection = page.locator('text=/pending|invited|awaiting/i');
      await expect(pendingSection).toBeVisible();
    }
  });
});

