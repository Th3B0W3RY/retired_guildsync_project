/**
 * Guild Member Invite Page Object Model
 * Encapsulates all interactions with the guild member invitation form
 */

export class GuildMemberInvitePage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    emailInput: 'input[name="email"], input[type="email"]',
    roleSelect: 'select[name*="role"]',
    submitButton: 'button[type="submit"], button:has-text("Invite"), button:has-text("Send")',
    inviteLinkForm: 'form[action*="invite_links"]',
    inviteLinkButton: 'form[action*="invite_links"] button[type="submit"]',
    inviteLinkInput: '#invite-link-url',
    discordWarning: 'text=Bot Not Connected, div:has-text("Bot Not Connected")',
    connectBotButton: 'button:has-text("Connect Bot"), a:has-text("Connect Bot"), button:has-text("Connect Bot To Guild Discord")',
    successMessage: 'text=/invited|sent|success/i',
    errorMessage: 'text=/email|invalid|format|limit|maximum|member|plan|already|exists|duplicate/i',
    pendingSection: 'text=/pending|invited|awaiting/i'
  };

  /**
   * Navigate to member invitation page for a guild
   */
  async goto(guildId) {
    await this.page.goto(`/guilds/${guildId}/members/invite`);
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000); // Give page time to render
  }

  /**
   * Navigate to members list page
   */
  async gotoMembersList(guildId) {
    await this.page.goto(`/guilds/${guildId}/members`);
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
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
      test.skip('Discord bot not connected. Skipping member invitation test.');
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

    console.log('[Guild Member Invite] Discord bot not connected. Attempting to connect...');
    await connectButton.click();
    await this.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    await this.page.waitForTimeout(3000);
    
    // Navigate back to invite page to check if connection was successful
    await this.goto(guildId);
    
    // Check if connection was successful (warning should be gone, form should be visible)
    const stillWarning = await this.page.locator('text=Bot Not Connected').isVisible({ timeout: 3000 }).catch(() => false);
    const formVisible = await this.isFormAccessible();
    
    return !stillWarning && formVisible;
  }

  /**
   * Verify form is accessible (email field exists)
   */
  async isFormAccessible() {
    const emailField = this.page.locator(this.selectors.emailInput);
    return await emailField.isVisible({ timeout: 5000 }).catch(() => false);
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
        `Member invitation form not accessible.\n` +
        `Current URL: ${currentUrl}\n` +
        `Page may require Discord bot connection or form may not be loading.\n` +
        `Page content preview: ${pageText.substring(0, 200)}`
      );
    }
  }

  /**
   * Fill email address
   */
  async fillEmail(email) {
    const emailField = this.page.locator(this.selectors.emailInput);
    await emailField.waitFor({ state: 'visible', timeout: 5000 });
    await emailField.fill(email);
  }

  /**
   * Select role if dropdown exists
   */
  async selectRole(role) {
    const roleSelect = this.page.locator(this.selectors.roleSelect);
    const roleExists = await roleSelect.isVisible({ timeout: 2000 }).catch(() => false);
    if (roleExists) {
      await roleSelect.selectOption(role);
    }
    return roleExists;
  }

  /**
   * Submit the invitation form
   */
  async submit() {
    const submitButton = this.page.locator(this.selectors.submitButton).first();
    await submitButton.waitFor({ state: 'visible', timeout: 5000 });
    await submitButton.click();
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  }

  /**
   * Submit and wait for success
   */
  async submitAndWaitForSuccess() {
    await this.submit();
    
    // Wait for success message or redirect
    const successMessage = await this.page.locator(this.selectors.successMessage).isVisible({ timeout: 5000 }).catch(() => false);
    const redirected = await this.page.waitForURL(/\/members/, { timeout: 5000 }).catch(() => false);
    
    if (!successMessage && !redirected) {
      throw new Error('Member invitation did not succeed - no success message or redirect');
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
   * Invite a member with email and optional role
   */
  async inviteMember(email, role = null) {
    await this.fillEmail(email);
    
    if (role) {
      await this.selectRole(role);
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

  /**
   * Create a shareable invite link via the invite management UI.
   * Navigates to the page, clicks "Generate invite link", and returns the token
   * extracted from the displayed URL input. Returns null if the button is not
   * present or the token cannot be read (e.g. feature is plan-gated).
   */
  async createInviteLink(guildId) {
    await this.goto(guildId);

    const btn = this.page.locator(this.selectors.inviteLinkButton).first();
    const btnVisible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
    if (!btnVisible) return null;

    await btn.click();
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const linkInput = this.page.locator(this.selectors.inviteLinkInput);
    const inputVisible = await linkInput.isVisible({ timeout: 3000 }).catch(() => false);
    if (!inputVisible) return null;

    const linkUrl = await linkInput.inputValue().catch(() => null);
    if (!linkUrl) return null;

    const match = linkUrl.match(/\/join\/([^/?#]+)/);
    return match ? match[1] : null;
  }

  /**
   * Check if pending invitations section is visible
   */
  async hasPendingSection() {
    const pendingSection = this.page.locator(this.selectors.pendingSection);
    return await pendingSection.isVisible({ timeout: 3000 }).catch(() => false);
  }
}
