/**
 * Message Center Page Object
 * Encapsulates interactions with /guilds/:id/message_center
 */

export class MessageCenterPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    root: '[data-controller="message-center"]',
    searchInput: '#recipient-search, [data-message-center-target="searchInput"]',
    searchDropdown: '[data-message-center-target="searchDropdown"], [data-message-center-target="searchResults"]',
    emptyState: '[data-message-center-target="emptyState"]',
    composer: '[data-message-center-target="composer"]',
    sendBtn: '[data-message-center-target="sendBtn"]',
    thread: '[data-message-center-target="thread"]',
    charCount: '[data-message-center-target="charCount"]'
  };

  async goto(guildId) {
    await this.page.goto(`/guilds/${guildId}/message_center`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  isPlanGated() {
    const url = this.page.url();
    return url.includes('/pricing') || url.includes('/subscriptions') || url.includes('/upgrade');
  }

  isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/mfa');
  }

  async isStimulusRootVisible() {
    return this.page.locator(this.selectors.root).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isSearchInputVisible() {
    return this.page.locator(this.selectors.searchInput).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isComposerVisible() {
    return this.page.locator(this.selectors.composer).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isSendButtonVisible() {
    return this.page.locator(this.selectors.sendBtn).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isEmptyStateVisible() {
    return this.page.locator(this.selectors.emptyState).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async searchRecipients(query) {
    const input = this.page.locator(this.selectors.searchInput).first();
    await input.fill(query);
    await this.page.waitForTimeout(600);
  }

  async isSearchDropdownVisible() {
    return this.page.locator(this.selectors.searchDropdown).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async getFirstSearchResult() {
    const dropdown = this.page.locator(this.selectors.searchDropdown).first();
    const item = dropdown.locator('li, [role="option"], button, div[data-recipient-id]').first();
    return item;
  }

  async typeMessage(text) {
    const composer = this.page.locator(this.selectors.composer).first();
    await composer.fill(text);
  }

  async clickSend() {
    await this.page.locator(this.selectors.sendBtn).first().click();
    await this.page.waitForTimeout(800);
  }

  async getThreadMessageCount() {
    return this.page.locator(`${this.selectors.thread} [data-message-id], ${this.selectors.thread} article, ${this.selectors.thread} .message`).count();
  }
}
