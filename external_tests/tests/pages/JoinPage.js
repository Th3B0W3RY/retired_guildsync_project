/**
 * Join Page Object
 * Encapsulates interactions with /join/:token (public) and /join/complete (authenticated).
 */

export class JoinPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    signInLink: 'a[href*="/login"], a[href*="sign_in"]',
    createAccountLink: 'a[href*="sign_up"], a[href*="register"]',
    errorAlert: '[role="alert"]'
  };

  async goto(token) {
    await this.page.goto(`/join/${token}`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoComplete() {
    await this.page.goto('/join/complete');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  isServerError() {
    const url = this.page.url();
    return url.includes('/500') || url.includes('/error');
  }

  isOnJoinPage(token) {
    return this.page.url().includes(`/join/${token}`);
  }

  isOnDashboard() {
    return this.page.url().includes('/dashboard');
  }

  isOnGuild() {
    return this.page.url().includes('/guilds/');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isSignInLinkVisible() {
    return this.page.locator(this.selectors.signInLink).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async isCreateAccountLinkVisible() {
    return this.page.locator(this.selectors.createAccountLink).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async hasErrorAlert() {
    return this.page.locator(this.selectors.errorAlert).isVisible({ timeout: 3000 }).catch(() => false);
  }
}
