/**
 * Account Settings Page Object
 * Encapsulates interactions with /account/settings.
 */

export class AccountSettingsPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    passwordLink: 'a[href*="/password/edit"], a[href*="edit_password"]',
    localeSelect: 'select[name="preferred_locale"], select#preferred_locale',
    localeForm: 'form[action*="locale"]',
    localeSubmitButton: 'button[type="submit"]',
    mfaSection: 'text=/mfa|two.factor|authenticator/i',
    discordSection: 'text=/discord/i'
  };

  async goto() {
    await this.page.goto('/account/settings');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/mfa');
  }

  isOnSettingsPage() {
    return this.page.url().includes('/account/settings');
  }

  isServerError() {
    const url = this.page.url();
    return url.includes('/500') || url.includes('/error');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isPasswordLinkVisible() {
    return this.page.locator(this.selectors.passwordLink).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isLocaleSelectorVisible() {
    return this.page.locator(this.selectors.localeSelect).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async getLocaleOptionCount() {
    return this.page.locator(`${this.selectors.localeSelect} option`).count();
  }

  async selectLocale(locale) {
    await this.page.locator(this.selectors.localeSelect).first().selectOption(locale);
  }

  async submitLocaleForm() {
    const form = this.page.locator(this.selectors.localeForm).first();
    await form.locator(this.selectors.localeSubmitButton).first().click();
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async isMfaSectionVisible() {
    return this.page.locator(this.selectors.mfaSection).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isDiscordSectionVisible() {
    return this.page.locator(this.selectors.discordSection).first().isVisible({ timeout: 5000 }).catch(() => false);
  }
}
