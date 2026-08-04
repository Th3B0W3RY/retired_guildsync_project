/**
 * Gear Page Object
 * Encapsulates interactions with guild gear tracking pages:
 *   /guilds/:id/members/gear  (index)
 *   /guilds/:id/gear/upload   (upload — file input)
 *   /guilds/:id/gear/request  (request update — JSON)
 */

export class GearPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    bulkRequestMissing: '#bulk-request-missing-btn',
    bulkRequestOutdated: '#bulk-request-outdated-btn',
    bulkRequestAll: '#bulk-request-all-btn',
    viewPendingBtn: '#view-pending-requests-btn',
    fileInput: 'input[type="file"]',
    statusFilterLinks: 'a[href*="status="]',
    memberRow: 'table tbody tr, [data-member-id]'
  };

  async goto(guildId) {
    await this.page.goto(`/guilds/${guildId}/members/gear`);
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

  isServerError() {
    const url = this.page.url();
    return url.includes('/500') || url.includes('/error');
  }

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async hasBulkRequestButtons() {
    const any = this.page.locator(
      `${this.selectors.bulkRequestMissing}, ${this.selectors.bulkRequestOutdated}, ${this.selectors.bulkRequestAll}`
    ).first();
    return any.isVisible({ timeout: 3000 }).catch(() => false);
  }

  async hasStatusFilterLinks() {
    return this.page.locator(this.selectors.statusFilterLinks).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async hasViewPendingButton() {
    return this.page.locator(this.selectors.viewPendingBtn).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  async clickBulkRequestAll() {
    await this.page.locator(this.selectors.bulkRequestAll).first().click();
    await this.page.waitForTimeout(500);
  }

  async clickBulkRequestMissing() {
    await this.page.locator(this.selectors.bulkRequestMissing).first().click();
    await this.page.waitForTimeout(500);
  }

  async filterByStatus(status) {
    await this.page.goto(`${this.page.url().split('?')[0]}?status=${status}`);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  }

  async hasFileInput() {
    return this.page.locator(this.selectors.fileInput).first().isVisible({ timeout: 3000 }).catch(() => false);
  }
}
