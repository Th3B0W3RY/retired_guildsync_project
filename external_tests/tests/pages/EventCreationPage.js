/**
 * Event Creation Page Object Model
 * Encapsulates all interactions with the event creation form
 */

export class EventCreationPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    titleInput: 'input[name="event[title]"], input[type="text"][placeholder*="title" i]',
    dateInput: 'input[type="date"], input[name*="date"], input[name*="scheduled_at"]',
    timeInput: 'input[type="time"], input[name*="time"]',
    durationInput: 'input[name*="duration"], input[type="number"]',
    submitButton: 'input[type="submit"], button[type="submit"]',
    discordWarning: 'text=Bot Not Connected, div:has-text("Bot Not Connected")',
    connectBotButton: 'button:has-text("Connect Bot"), a:has-text("Connect Bot"), button:has-text("Connect Bot To Guild Discord")',
    successMessage: 'text=/created|scheduled|success/i',
    errorMessage: 'text=/title|length|minimum|short|date|past|future|invalid/i'
  };

  /**
   * Navigate to event creation page for a guild
   */
  async goto(guildId, eventType = 'schedule') {
    const path = eventType === 'guild-battle' 
      ? `/guilds/${guildId}/events/guild-battle`
      : `/guilds/${guildId}/events/schedule`;
    
    await this.page.goto(path);
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000); // Give page time to render
  }

  /**
   * Check if Discord bot is connected
   * Returns true if connected (no warning), false if not connected (warning visible)
   */
  async isDiscordBotConnected() {
    const discordWarning = this.page.locator(this.selectors.discordWarning);
    const warningVisible = await discordWarning.isVisible({ timeout: 5000 }).catch(() => false);
    return !warningVisible;
  }

  /**
   * Check if Discord warning is visible and skip test if needed
   * Returns true if should skip, false if can continue
   */
  async checkDiscordAndSkip(test) {
    const isConnected = await this.isDiscordBotConnected();
    if (!isConnected) {
      test.skip('Discord bot not connected. Skipping event creation test.');
      return true;
    }
    return false;
  }

  /**
   * Attempt to connect Discord bot
   * Returns true if connection successful or attempted, false if button not found
   */
  async attemptDiscordConnection(guildId) {
    const connectButton = this.page.locator(this.selectors.connectBotButton).first();
    const connectButtonVisible = await connectButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (!connectButtonVisible) {
      return false;
    }

    console.log('[Event Creation] Discord bot not connected. Attempting to connect...');
    await connectButton.click();
    await this.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    await this.page.waitForTimeout(3000);
    
    // Navigate back to event page to check if connection was successful
    await this.goto(guildId);
    
    // Check if connection was successful (warning should be gone, form should be visible)
    const stillWarning = await this.page.locator('text=Bot Not Connected').isVisible({ timeout: 3000 }).catch(() => false);
    const formVisible = await this.isFormAccessible();
    
    return !stillWarning && formVisible;
  }

  /**
   * Verify form is accessible (title field exists)
   */
  async isFormAccessible() {
    const titleField = this.page.locator(this.selectors.titleInput);
    return await titleField.isVisible({ timeout: 5000 }).catch(() => false);
  }

  /**
   * Ensure form is accessible, throw error if not
   */
  async ensureFormAccessible() {
    const formAccessible = await this.isFormAccessible();
    
    if (!formAccessible) {
      const currentUrl = this.page.url();
      const pageText = await this.page.textContent('body').catch(() => '');
      
      // Check if we were redirected to login
      if (currentUrl.includes('/login') || currentUrl.includes('/sign_in')) {
        throw new Error('Session lost - redirected to login page');
      }
      
      // Check if Discord warning is actually there but selector didn't match
      const botNotConnected = await this.page.locator('text=Bot Not Connected').isVisible({ timeout: 2000 }).catch(() => false);
      const guildSyncBot = await this.page.locator('text=/GuildSync.*bot/i').isVisible({ timeout: 2000 }).catch(() => false);
      
      if (botNotConnected || guildSyncBot) {
        throw new Error('Discord bot not connected - form not accessible');
      }
      
      throw new Error(
        `Event creation form not accessible.\n` +
        `Current URL: ${currentUrl}\n` +
        `Page may require Discord bot connection or form may not be loading.\n` +
        `Page content preview: ${pageText.substring(0, 200)}`
      );
    }
  }

  /**
   * Fill event title
   */
  async fillTitle(title) {
    const titleField = this.page.locator(this.selectors.titleInput);
    await titleField.waitFor({ state: 'visible', timeout: 5000 });
    await titleField.fill(title);
  }

  /**
   * Fill event date if field exists
   */
  async fillDate(dateString) {
    const dateField = this.page.locator(this.selectors.dateInput);
    const dateExists = await dateField.isVisible({ timeout: 2000 }).catch(() => false);
    if (dateExists) {
      await dateField.fill(dateString);
    }
    return dateExists;
  }

  /**
   * Fill event time if field exists
   */
  async fillTime(timeString) {
    const timeField = this.page.locator(this.selectors.timeInput);
    const timeExists = await timeField.isVisible({ timeout: 2000 }).catch(() => false);
    if (timeExists) {
      await timeField.fill(timeString);
    }
    return timeExists;
  }

  /**
   * Fill event duration if field exists
   */
  async fillDuration(duration) {
    const durationField = this.page.locator(this.selectors.durationInput);
    const durationExists = await durationField.isVisible({ timeout: 2000 }).catch(() => false);
    if (durationExists) {
      await durationField.fill(String(duration));
    }
    return durationExists;
  }

  /**
   * Submit the event creation form
   */
  async submit() {
    const submitButton = this.page.locator(this.selectors.submitButton).first();
    await submitButton.waitFor({ state: 'visible', timeout: 5000 });
    
    const [response] = await Promise.all([
      this.page.waitForResponse(resp => 
        resp.url().includes('/events') && (resp.request().method() === 'POST' || resp.status() === 302)
      ).catch(() => null),
      submitButton.click()
    ]);
    
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    return response;
  }

  /**
   * Submit and wait for success
   */
  async submitAndWaitForSuccess() {
    await this.submit();
    
    // Wait for success message or redirect
    const successMessage = await this.page.locator(this.selectors.successMessage).isVisible({ timeout: 5000 }).catch(() => false);
    const redirected = await this.page.waitForURL(/\/events|\/guilds\/\d+/, { timeout: 5000 }).catch(() => false);
    
    if (!successMessage && !redirected) {
      throw new Error('Event creation did not succeed - no success message or redirect');
    }
  }

  /**
   * Submit and wait for error
   */
  async submitAndWaitForError() {
    await this.submit();
    
    // Wait for error message
    const errorMessage = this.page.locator(this.selectors.errorMessage);
    await errorMessage.waitFor({ state: 'visible', timeout: 5000 });
    return errorMessage;
  }

  /**
   * Create a complete event with all fields
   */
  async createEvent({ title, date, time, duration }) {
    if (title) {
      await this.fillTitle(title);
    }
    
    if (date) {
      await this.fillDate(date);
    }
    
    if (time) {
      await this.fillTime(time);
    }
    
    if (duration) {
      await this.fillDuration(duration);
    }
    
    await this.submitAndWaitForSuccess();
  }

  /**
   * Expect error message to be visible
   */
  async expectError(messagePattern) {
    const errorLocator = this.page.locator(`text=/${messagePattern}/i`);
    await errorLocator.waitFor({ state: 'visible', timeout: 5000 });
  }
}
