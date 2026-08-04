/**
 * Member Stats Page Object
 * Encapsulates interactions with /guilds/:id/members/stats/:user_id
 * and the inline stat editing endpoint PATCH /guilds/:id/members/stats/:user_id/fields
 */

export class MemberStatsPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    statsHeading: '#member_extracted_stats_heading',
    statCountLine: '#member_stats_stat_count_line',
    backLink: 'a[href*="gear"], a:has-text("Back"), a:has-text("Scanner")',
    emptyState: '[class*="empty"], [class*="no-data"], text=/no snapshot|no gear|no stats/i',
    statRow: '[data-stat-key], [class*="stat-row"], tbody tr'
  };

  async goto(guildId, userId) {
    await this.page.goto(`/guilds/${guildId}/members/stats/${userId}`);
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

  isRedirectedAway(guildId, userId) {
    const url = this.page.url();
    return !url.includes(`/members/stats/${userId}`);
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isStatsHeadingVisible() {
    return this.page.locator(this.selectors.statsHeading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isStatCountLineVisible() {
    return this.page.locator(this.selectors.statCountLine).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async getStatRowCount() {
    return this.page.locator(this.selectors.statRow).count();
  }

  async hasBackLink() {
    return this.page.locator(this.selectors.backLink).first().isVisible({ timeout: 3000 }).catch(() => false);
  }
}
