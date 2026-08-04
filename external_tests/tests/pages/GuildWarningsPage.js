/**
 * Guild Warnings Page Object
 * Encapsulates interactions with the guild warnings page (/guilds/:id/warnings).
 */

export class GuildWarningsPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    memberSelect: 'select[name="user_id"]',
    reasonTextarea: 'textarea[name="reason"]',
    submitButton: 'input[type="submit"], button[type="submit"]',
    errorAlert: '[role="alert"]'
  };

  async goto(guildId) {
    await this.page.goto(`/guilds/${guildId}/warnings`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await this.page.waitForTimeout(500);
  }

  async gotoMeWarnings(guildId) {
    await this.page.goto(`/guilds/${guildId}/warnings/me`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await this.page.waitForTimeout(500);
  }

  isPlanGated() {
    const url = this.page.url();
    return url.includes('/pricing') || url.includes('/subscriptions');
  }

  isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/mfa');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isMemberSelectVisible() {
    return this.page.locator(this.selectors.memberSelect).isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isReasonTextareaVisible() {
    return this.page.locator(this.selectors.reasonTextarea).isVisible({ timeout: 5000 }).catch(() => false);
  }

  async submitWarningForm() {
    const btn = this.page.locator(this.selectors.submitButton).first();
    await btn.click();
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(500);
  }

  async hasErrorAlert() {
    return this.page.locator(this.selectors.errorAlert).isVisible({ timeout: 3000 }).catch(() => false);
  }

  isOnWarningsPage(guildId) {
    return this.page.url().includes(`/guilds/${guildId}/warnings`);
  }
}
