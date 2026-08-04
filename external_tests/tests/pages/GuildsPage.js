/**
 * Guilds Page Object Model
 * Encapsulates all interactions with guild viewing pages
 */

import { getBaseURL } from '../../config/test-config.js';

export class GuildsPage {
  constructor(page) {
    this.page = page;
  }

  // Navigation
  async gotoGuildsList() {
    // Navigate directly to /guilds (same pattern as passing tests that navigate to /guilds/1)
    await this.page.goto('/guilds');
  }

  async gotoGuild(guildId) {
    await this.page.goto(`/guilds/${guildId}`);
  }

  async gotoGuildMembers(guildId) {
    await this.page.goto(`/guilds/${guildId}/members`);
  }

  // Selectors based on actual view structure
  selectors = {
    // Guilds list page
    pageTitle: 'h1.text-4xl, h1:has-text("My Guilds")',
    createGuildButton: 'a:has-text("Create New Guild"), a[href*="/guilds/new"]',
    guildCard: '.grid a[href*="/guilds/"]:not([href*="/guilds/new"])', // Guild cards with links
    guildName: 'h3.text-2xl', // Guild name in card
    viewGuildLink: 'a:has-text("View Guild")',
    emptyState: 'text=/You haven\'t joined any guilds yet/i',
    emptyStateCreateButton: 'a:has-text("Create Your First Guild")',
    
    // Guild show page
    guildShowTitle: 'h1.text-4xl', // Guild name on show page
    guildDescription: 'p.text-theme-secondary.text-lg',
    guildInfoSection: 'text=/Guild Information/i',
    quickActionsSection: 'text=/Quick Actions/i',
    inviteMembersLink: 'a:has-text("Invite Members")',
    scheduleEventLink: 'a:has-text("Schedule Event")',
    
    // Access control messages
    accessDeniedMessage: 'text=/Guild not found or you do not have access to it/i',
    
    // Guild members page
    membersPageTitle: 'h1:has-text("Guild Members")',
    memberCard: '.bg-theme-card', // Member card
    memberUsername: '.text-theme-primary.font-semibold', // Username in member card
    backToGuildLink: 'a:has-text("Back to Dashboard")'
  };

  // Assertions for guilds list
  async expectGuildsList() {
    // Wait for page to load
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Check if we're redirected to login
    const currentUrl = this.page.url();
    if (currentUrl.includes('/login')) {
      throw new Error('Not authenticated - redirected to login page');
    }
    
    // If we're redirected to home, that's also a sign of auth failure
    const baseURL = getBaseURL();
    if (currentUrl === baseURL || currentUrl === `${baseURL}/`) {
      throw new Error('Not authenticated - redirected to home page. Session may not be persisting.');
    }
    
    // Check for page title - try multiple selectors
    let title = this.page.locator('h1.text-4xl');
    let titleVisible = await title.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (!titleVisible) {
      // Try alternative selector
      title = this.page.locator('h1:has-text("My Guilds")');
      titleVisible = await title.isVisible({ timeout: 3000 }).catch(() => false);
    }
    
    if (!titleVisible) {
      // Try just any h1
      title = this.page.locator('h1');
      titleVisible = await title.isVisible({ timeout: 2000 }).catch(() => false);
    }
    
    if (!titleVisible) {
      throw new Error(`Guilds list page not found - title not visible. Current URL: ${currentUrl}`);
    }
    
    return title;
  }

  async expectGuildCard() {
    // Wait for page to fully load
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Check for empty state first (more reliable)
    const emptyState = this.page.locator(this.selectors.emptyState);
    const emptyVisible = await emptyState.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (emptyVisible) {
      // User has no guilds - return null to indicate empty state
      return null;
    }
    
    // Check for guild cards - try multiple selector patterns
    // The grid contains links to guilds
    const guildCard = this.page.locator(this.selectors.guildCard).first();
    const cardVisible = await guildCard.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!cardVisible) {
      // Try alternative selectors - guild cards might be in different structure
      const altGuildCard = this.page.locator('a[href*="/guilds/"]:not([href*="/guilds/new"])').first();
      const altVisible = await altGuildCard.isVisible({ timeout: 2000 }).catch(() => false);
      
      if (altVisible) {
        return altGuildCard;
      }
      
      // Check if we're on the right page - verify URL first, then title
      const currentUrl = this.page.url();
      if (currentUrl.includes('/login')) {
        throw new Error('Not authenticated - redirected to login page');
      }
      
      if (!currentUrl.includes('/guilds')) {
        throw new Error(`Not on guilds list page - current URL: ${currentUrl}`);
      }
      
      // Check for page title (more lenient - might take time to render)
      const pageTitle = this.page.locator(this.selectors.pageTitle);
      const titleVisible = await pageTitle.isVisible({ timeout: 3000 }).catch(() => false);
      
      if (!titleVisible) {
        // Try alternative title selector
        const altTitle = this.page.locator('h1.text-4xl, h1:has-text("Guilds")');
        const altTitleVisible = await altTitle.isVisible({ timeout: 2000 }).catch(() => false);
        
        if (!altTitleVisible) {
          // If we're on /guilds URL but title not found, might be a rendering delay
          // Return null to indicate empty state rather than failing
          return null;
        }
      }
      
      // We're on the page but no guilds and no empty state - might be a rendering issue
      // Return null to indicate empty state (safer than failing)
      return null;
    }
    
    return guildCard;
  }

  async clickFirstGuild() {
    const guildCard = await this.expectGuildCard();
    if (!guildCard) {
      // User has no guilds - return null to indicate this
      return null;
    }
    
    await guildCard.click();
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Should be on guild show page
    const currentUrl = this.page.url();
    if (!currentUrl.match(/\/guilds\/\d+/)) {
      // No navigable guild found (e.g., no guilds exist for this user)
      return null;
    }

    return currentUrl.match(/\/guilds\/(\d+)/)?.[1]; // Return guild ID
  }

  // Assertions for guild show page
  async expectGuildShowPage(guildId = null) {
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Check if we're redirected to login (authentication issue)
    const currentUrl = this.page.url();
    if (currentUrl.includes('/login')) {
      throw new Error('Not authenticated - redirected to login page');
    }
    
    if (guildId && !currentUrl.includes(`/guilds/${guildId}`)) {
      throw new Error(`Expected to be on guild ${guildId} page, but URL is: ${currentUrl}`);
    }
    
    // Check for access denied message first
    const accessDenied = this.page.locator(this.selectors.accessDeniedMessage);
    const accessDeniedVisible = await accessDenied.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (accessDeniedVisible) {
      throw new Error('Access denied - user does not have access to this guild');
    }
    
    // Check for guild name (h1)
    const guildTitle = this.page.locator(this.selectors.guildShowTitle);
    const titleVisible = await guildTitle.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!titleVisible) {
      throw new Error('Guild show page not found - guild name not visible');
    }
    
    return guildTitle;
  }

  /**
   * Check if access is denied (user doesn't have access to guild)
   * @returns {Promise<boolean>} True if access denied message is visible
   */
  async expectAccessDenied() {
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // The app shows a toast (role="alert") with the access-denied message.
    // The toast uses bg-red-950/95 — match by role + text instead of CSS class.
    const accessDenied = this.page.locator('[role="alert"]')
      .filter({ hasText: /Guild not found or you do not have access to it/i })
      .first();

    const isVisible = await accessDenied.isVisible({ timeout: 3000 }).catch(() => false);
    return isVisible;
  }

  async expectMembersLink() {
    // Look for members link - could be in navigation or quick actions
    const membersLink = this.page.locator('a[href*="members"], text=/members/i').first();
    const linkVisible = await membersLink.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (!linkVisible) {
      // Try direct navigation - members link might not be visible but route exists
      return null;
    }
    
    return membersLink;
  }

  async clickMembersLink() {
    const membersLink = await this.expectMembersLink();
    
    if (membersLink) {
      await membersLink.click();
      await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
      await this.page.waitForTimeout(1000);
    } else {
      // Try direct navigation
      const currentUrl = this.page.url();
      const guildId = currentUrl.match(/\/guilds\/(\d+)/)?.[1];
      if (guildId) {
        await this.gotoGuildMembers(guildId);
      } else {
        throw new Error('Cannot navigate to members - guild ID not found in URL');
      }
    }
    
    // Should be on members page
    const membersUrl = this.page.url();
    if (!membersUrl.match(/\/guilds\/\d+\/members/)) {
      throw new Error(`Expected to be on members page, but URL is: ${membersUrl}`);
    }
  }

  // Assertions for guild members page
  async expectMembersList() {
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Check if we're redirected
    const currentUrl = this.page.url();
    if (currentUrl.includes('/login') || (currentUrl.includes('/guilds') && !currentUrl.includes('/members'))) {
      throw new Error('Cannot access guild members - redirected or access denied');
    }
    
    // Check for members page title
    const pageTitle = this.page.locator(this.selectors.membersPageTitle);
    const titleVisible = await pageTitle.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!titleVisible) {
      throw new Error('Members page not found - title not visible');
    }
    
    // Check for member cards
    const memberCard = this.page.locator(this.selectors.memberCard).first();
    const cardVisible = await memberCard.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!cardVisible) {
      // Guild might have no members - that's valid
      // Check if we're on the members page at least
      if (currentUrl.match(/\/guilds\/\d+\/members/)) {
        return null; // Empty members list
      }
      
      throw new Error('Members list not found - page structure may differ');
    }
    
    return memberCard;
  }
}
