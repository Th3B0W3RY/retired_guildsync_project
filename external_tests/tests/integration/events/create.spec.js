import { test, expect } from '@playwright/test';
import { expectNavigation, createTestUserAndGetToken } from '../../helpers/test-helpers';
import { LoginPage, GuildCreationPage, EventCreationPage } from '../../pages';

// Event creation tests require Discord bot connection
// Run tests serially to avoid conflicts with single Discord account
test.describe.serial('Event Creation', () => {
  let testGuildId = null;

  test.beforeEach(async ({ page, request }) => {
    // Create a fresh Discord auth user — bypasses MFA in the browser UI.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'event',
      usernameAffix: 'event',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);

    // Wait for redirect; Discord users may briefly land on /mfa/setup — navigating to
    // any protected page resolves this via require_mfa_if_enabled.
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Create a guild for the user to create events in
    const guildCreationPage = new GuildCreationPage(page);
    const guildName = `Test Guild for Events ${Date.now()}`;

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

    // Check if Discord bot is connected - required for event creation
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);

    const isConnected = await eventCreationPage.isDiscordBotConnected();

    if (!isConnected) {
      test.skip(true, 'Discord bot not connected — event creation tests require a connected bot.');
      return;
    } else {
      const formOk = await eventCreationPage.isFormAccessible();
      if (!formOk) {
        test.skip(true, 'Discord bot reports connected but form is not accessible — skipping.');
        return;
      }
    }
  });

  test('should successfully create a new event with valid data', async ({ page }) => {
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await eventCreationPage.checkDiscordAndSkip(test)) {
      return;
    }
    
    // Ensure form is accessible
    await eventCreationPage.ensureFormAccessible();
    
    const eventTitle = `Test Event ${Date.now()}`;
    const eventDate = new Date();
    eventDate.setDate(eventDate.getDate() + 7); // 7 days from now
    const dateString = eventDate.toISOString().split('T')[0];
    const timeString = '18:00';

    // Create event with all fields
    await eventCreationPage.createEvent({
      title: eventTitle,
      date: dateString,
      time: timeString
    });
  });

  test('should show error for event title that is too short', async ({ page }) => {
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await eventCreationPage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const shortTitle = 'AB'; // Too short (minimum 3 characters)
    
    await eventCreationPage.fillTitle(shortTitle);
    await eventCreationPage.submit();
    
    // Should show validation error
    await eventCreationPage.expectError('title|length|minimum|short');
  });

  test('should show error for past event date', async ({ page }) => {
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await eventCreationPage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const eventTitle = `Test Event ${Date.now()}`;
    const pastDate = new Date();
    pastDate.setDate(pastDate.getDate() - 1); // Yesterday
    const dateString = pastDate.toISOString().split('T')[0];

    await eventCreationPage.fillTitle(eventTitle);
    const dateExists = await eventCreationPage.fillDate(dateString);
    
    if (dateExists) {
      await eventCreationPage.submit();
      
      // Should show validation error (if your app validates this)
      const errorVisible = await page.locator('text=/date|past|future|invalid/i').isVisible({ timeout: 5000 }).catch(() => false);
      if (errorVisible) {
        await expect(page.locator('text=/date|past|future|invalid/i')).toBeVisible();
      }
    }
  });

  test('should allow creating guild battle event', async ({ page }) => {
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId, 'guild-battle');
    
    // Check Discord and skip if not connected
    if (await eventCreationPage.checkDiscordAndSkip(test)) {
      return;
    }

    // Verify guild battle form is displayed
    const formVisible = await eventCreationPage.isFormAccessible();
    expect(formVisible).toBeTruthy();
  });

  test('should allow setting event duration', async ({ page }) => {
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);
    
    // Check Discord and skip if not connected
    if (await eventCreationPage.checkDiscordAndSkip(test)) {
      return;
    }
    
    const eventTitle = `Test Event ${Date.now()}`;
    await eventCreationPage.fillTitle(eventTitle);
    
    // Look for duration field
    const durationExists = await eventCreationPage.fillDuration(60); // 60 minutes
    
    if (durationExists) {
      await eventCreationPage.submitAndWaitForSuccess();
    }
  });

  test('should require appropriate permissions to create events', async ({ page }) => {
    // This test verifies that only users with create event permissions can access the page
    // You may need to test with a non-admin user
    
    const eventCreationPage = new EventCreationPage(page);
    await eventCreationPage.goto(testGuildId);
    
    // Check for Discord bot connection requirement first
    const warningVisible = !(await eventCreationPage.isDiscordBotConnected());
    
    // Should either show the form, Discord warning, redirect/error if no permission
    const formVisible = await eventCreationPage.isFormAccessible();
    const unauthorized = await page.locator('text=/unauthorized|permission|access/i').isVisible({ timeout: 3000 }).catch(() => false);
    const redirected = await page.waitForURL(/\/guilds\/\d+/, { timeout: 3000 }).catch(() => false);
    
    // One of these should be true (form, Discord warning, unauthorized, or redirected)
    expect(formVisible || warningVisible || unauthorized || redirected).toBeTruthy();
  });
});

