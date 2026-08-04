/**
 * Guild Application Page Object
 * Encapsulates interactions with the guild application form (/guild_applications/new).
 *
 * The form uses `form_with url:` (not `model:`), so field names are unprefixed:
 *   discord_username, message, character_details, guild_id (hidden)
 */

export class GuildApplicationPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    guildSearchInput: '#guild-search-input',
    guildDropdown: '#guild-search-dropdown',
    dropdownOption: '#guild-search-dropdown .autocomplete-option, #guild-search-dropdown [data-guild-id]',
    discordUsername: '[name="discord_username"]',
    message: '[name="message"]',
    characterDetails: '[name="character_details"]',
    submitButton: '#guild-application-form input[type="submit"], #guild-application-form button[type="submit"]',
    errorAlert: '[role="alert"]',
    inlineError: '.bg-red-900\\/20, .bg-red-900\\/50'
  };

  async goto() {
    await this.page.goto('/guild_applications');
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  }

  async gotoNew() {
    await this.page.goto('/guild_applications/new');
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  }

  async isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/mfa');
  }

  async isGuildSearchVisible() {
    return this.page.locator(this.selectors.guildSearchInput).isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isDiscordUsernameVisible() {
    return this.page.locator(this.selectors.discordUsername).isVisible({ timeout: 5000 }).catch(() => false);
  }

  async searchForGuild(nameFragment) {
    const input = this.page.locator(this.selectors.guildSearchInput).first();
    await input.fill(nameFragment);
    await this.page.waitForTimeout(600); // debounce delay
  }

  async selectFirstDropdownOption() {
    const option = this.page.locator(this.selectors.dropdownOption).first();
    const visible = await option.isVisible({ timeout: 3000 }).catch(() => false);
    if (!visible) return false;
    await option.click();
    await this.page.waitForTimeout(300);
    return true;
  }

  async fillDiscordUsername(username) {
    await this.page.fill(this.selectors.discordUsername, username);
  }

  async fillMessage(text) {
    await this.page.fill(this.selectors.message, text);
  }

  async submit() {
    await this.page.click(this.selectors.submitButton);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await this.page.waitForTimeout(500);
  }

  async hasError() {
    const alertVisible = await this.page.locator(this.selectors.errorAlert).isVisible({ timeout: 2000 }).catch(() => false);
    const inlineVisible = await this.page.locator(this.selectors.inlineError).first().isVisible({ timeout: 2000 }).catch(() => false);
    return alertVisible || inlineVisible;
  }
}
