/**
 * Alliance Page Object
 * Encapsulates navigation and state checks for alliance-related pages.
 */

export class AlliancePage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1, main'
  };

  // --- Navigation ---

  async goto() {
    await this.page.goto('/alliances');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoNew() {
    await this.page.goto('/alliances/new');
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoById(allianceId) {
    await this.page.goto(`/alliances/${allianceId}`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoPendingInvites(guildId) {
    await this.page.goto(`/guilds/${guildId}/alliance_invites/pending`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoJoinRequestNew(guildId) {
    await this.page.goto(`/guilds/${guildId}/alliance_join_requests/new`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async gotoJoinStatus(guildId) {
    await this.page.goto(`/guilds/${guildId}/alliance_join_status`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  // --- State checks ---

  isPlanGated() {
    const url = this.page.url();
    return url.includes('/dashboard') || url.includes('/pricing') ||
      url.includes('/subscriptions') || url.includes('/upgrade');
  }

  isOnAuthPage() {
    const url = this.page.url();
    return url.includes('/login') || url.includes('/sign_in');
  }

  isServerError() {
    const url = this.page.url();
    return url.includes('/500') || url.includes('/error');
  }

  isOnAlliancesPage() {
    return this.page.url().includes('/alliances');
  }

  isOnDashboard() {
    return this.page.url().includes('/dashboard');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }
}
