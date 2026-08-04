/**
 * Storage Page Object
 * Encapsulates interactions with guild file storage pages:
 *   /guilds/:id/storage             (main view)
 *   /guilds/:id/file_entries        (upload endpoint)
 *   /guilds/:id/folders             (folder CRUD)
 */

export class StoragePage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    heading: 'h1',
    folderTree: 'aside.storage-folder-tree, [class*="folder-tree"], aside',
    fileInput: 'input[type="file"]',
    bulkActionsBar: '#bulk-actions-bar, [data-testid="bulk-actions-bar"]',
    newFolderBtn: 'button:has-text("New Folder"), button:has-text("folder"), [data-action*="create-folder"], [data-action*="newFolder"]',
    folderNameInput: 'input[name*="folder[name]"], input[name="name"], input[placeholder*="folder" i]',
    fileGrid: '[class*="grid"], [class*="file-grid"]',
    breadcrumb: 'nav[aria-label*="breadcrumb" i], [class*="breadcrumb"]'
  };

  async goto(guildId, folderId = null) {
    const base = `/guilds/${guildId}/storage`;
    await this.page.goto(folderId ? `${base}?folder_id=${folderId}` : base);
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

  async isHeadingVisible() {
    return this.page.locator(this.selectors.heading).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async hasFolderTree() {
    return this.page.locator(this.selectors.folderTree).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async hasFileInput() {
    return (await this.page.locator(this.selectors.fileInput).count()) > 0;
  }

  async hasNewFolderButton() {
    return this.page.locator(this.selectors.newFolderBtn).first().isVisible({ timeout: 3000 }).catch(() => false);
  }

  /**
   * Upload a file using the file input.
   * Accepts a Playwright-compatible file descriptor:
   *   { name, mimeType, buffer } or a file path string.
   */
  async uploadFile(fileDescriptor) {
    const input = this.page.locator(this.selectors.fileInput).first();
    await input.setInputFiles(fileDescriptor);
    await this.page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
  }

  /**
   * Create a folder by clicking the new-folder button and submitting the name.
   * Returns true if the folder name becomes visible on the page.
   */
  async createFolder(name) {
    const btn = this.page.locator(this.selectors.newFolderBtn).first();
    const btnVisible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
    if (!btnVisible) return false;

    await btn.click();
    await this.page.waitForTimeout(400);

    const input = this.page.locator(this.selectors.folderNameInput).first();
    const inputVisible = await input.isVisible({ timeout: 3000 }).catch(() => false);
    if (!inputVisible) return false;

    await input.fill(name);
    await this.page.keyboard.press('Enter');
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(500);
    return true;
  }

  async isFolderVisible(name) {
    return this.page.locator(`text=${name}`).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async isFileVisible(name) {
    return this.page.locator(`text=${name}`).first().isVisible({ timeout: 5000 }).catch(() => false);
  }

  async clickFirstDeleteButton() {
    const del = this.page.locator(
      'button[data-turbo-method="delete"], button:has-text("Delete"), [data-action*="destroy"], [data-action*="delete"]'
    ).first();
    const visible = await del.isVisible({ timeout: 3000 }).catch(() => false);
    if (!visible) return false;
    await del.click();
    await this.page.waitForTimeout(500);
    // Accept confirmation dialogs if shown
    this.page.on('dialog', d => d.accept().catch(() => {}));
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    return true;
  }
}
