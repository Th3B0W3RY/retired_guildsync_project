/**
 * Profile Settings Page Object
 * Encapsulates interactions with /profile/settings and /profile/complete.
 */

export class ProfileSettingsPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    avatarInput: 'input[type="file"][id="avatar-upload-input"], input[accept="image/*"]',
    avatarLabel: 'label[for="avatar-upload-input"], label:has-text("Upload"), label:has-text("Change")',
    usernameSection: 'text=/username/i'
  };

  async goto() {
    await this.page.goto('/profile/settings');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoComplete() {
    await this.page.goto('/profile/complete');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/mfa');
  }

  isOnSettingsPage() {
    return this.page.url().includes('/profile/settings');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async hasAvatarSection() {
    const inputPresent = (await this.page.locator(this.selectors.avatarInput).count()) > 0;
    const labelVisible = await this.page.locator(this.selectors.avatarLabel).first().isVisible({ timeout: 3000 }).catch(() => false);
    return inputPresent || labelVisible;
  }

  async isUsernameSectionVisible() {
    return this.page.locator(this.selectors.usernameSection).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isEmailVisible(email) {
    return this.page.locator(`text=${email}`).first().isVisible({ timeout: 5000 }).catch(() => false);
  }
}
