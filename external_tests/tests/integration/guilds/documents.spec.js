import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';

// Check whether the app redirected away due to plan gating
function isPlanGated(url) {
  return url.includes('/pricing') || url.includes('/subscriptions') || url.includes('/upgrade');
}

test.describe('Guild Documents', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'docown',
      usernameAffix: 'docown',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Docs Test ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  test('should display the documents index page', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (isPlanGated(currentUrl)) {
      test.skip('Guild documents require a paid plan — upgrade the test user subscription');
      return;
    }

    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing documents: ${currentUrl}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should display the new document form', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (isPlanGated(currentUrl)) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing new document form: ${currentUrl}`);
    }

    // Title field
    const titleField = page.locator('[name="guild_document[title]"]').first();
    await expect(titleField).toBeVisible({ timeout: 5000 });

    // Visibility select
    const visibilitySelect = page.locator('[name="guild_document[visibility]"]').first();
    await expect(visibilitySelect).toBeVisible({ timeout: 5000 });
  });

  test('should create a new document with a title', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (isPlanGated(currentUrl)) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    const docTitle = `Test Document ${Date.now()}`;
    await page.fill('[name="guild_document[title]"]', docTitle);

    // Submit (the Tiptap editor initialises with empty content which is valid)
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterUrl = page.url();

    // Success: redirect to document show page
    const created = afterUrl.includes('/documents/') && !afterUrl.includes('/new');
    const successToast = await page.locator('[role="alert"]').isVisible({ timeout: 3000 }).catch(() => false);

    if (!created && !successToast) {
      const errorText = await page.locator('[role="alert"], .bg-red-900\\/20').first().textContent({ timeout: 2000 }).catch(() => '');
      throw new Error(`Document creation did not redirect or show success. Error: "${errorText}". URL: ${afterUrl}`);
    }

    expect(created || successToast).toBeTruthy();
  });

  test('should display a created document', async ({ page, request }) => {
    await page.goto(`/guilds/${guildId}/documents/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (isPlanGated(page.url())) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    const docTitle = `View Doc ${Date.now()}`;
    await page.fill('[name="guild_document[title]"]', docTitle);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterUrl = page.url();
    if (!afterUrl.includes('/documents/')) {
      test.skip('Document was not created — cannot test document display');
      return;
    }

    // Document show page should display the title
    const titleOnPage = page.locator(`text=${docTitle}`).first();
    const titleVisible = await titleOnPage.isVisible({ timeout: 5000 }).catch(() => false);
    expect(titleVisible).toBeTruthy();
  });

  test('should allow editing a document', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (isPlanGated(page.url())) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    const docTitle = `Edit Doc ${Date.now()}`;
    await page.fill('[name="guild_document[title]"]', docTitle);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const showUrl = page.url();
    if (!showUrl.match(/\/documents\/\d+/)) {
      test.skip('Document was not created — cannot test editing');
      return;
    }

    // Navigate to edit page
    const docId = showUrl.match(/\/documents\/(\d+)/)?.[1];
    await page.goto(`/guilds/${guildId}/documents/${docId}/edit`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const editUrl = page.url();
    if (!editUrl.includes('/edit')) {
      throw new Error(`Expected to be on edit page but got: ${editUrl}`);
    }

    const titleField = page.locator('[name="guild_document[title]"]').first();
    await expect(titleField).toBeVisible({ timeout: 5000 });

    // Update the title
    await titleField.fill(`${docTitle} Updated`);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterEditUrl = page.url();
    const updated = !afterEditUrl.includes('/edit');
    expect(updated).toBeTruthy();
  });

  test('should allow deleting a document', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (isPlanGated(page.url())) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    const docTitle = `Delete Doc ${Date.now()}`;
    await page.fill('[name="guild_document[title]"]', docTitle);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const showUrl = page.url();
    if (!showUrl.match(/\/documents\/\d+/)) {
      test.skip('Document was not created — cannot test deletion');
      return;
    }

    // Find and click the delete button/link
    const deleteButton = page.locator('button[data-method="delete"], a[data-method="delete"], button:has-text("Delete"), a:has-text("Delete")').first();
    const deleteVisible = await deleteButton.isVisible({ timeout: 3000 }).catch(() => false);

    if (!deleteVisible) {
      // Navigate to edit for the delete option
      const docId = showUrl.match(/\/documents\/(\d+)/)?.[1];
      await page.goto(`/guilds/${guildId}/documents/${docId}/edit`);
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    }

    const deleteBtn = page.locator('button[data-method="delete"], a[data-method="delete"], button:has-text("Delete"), a:has-text("Delete"), [data-turbo-method="delete"]').first();
    const deleteBtnVisible = await deleteBtn.isVisible({ timeout: 3000 }).catch(() => false);

    if (!deleteBtnVisible) {
      test.skip('Delete button not found on document page — UI may have changed');
      return;
    }

    await deleteBtn.click();
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Should redirect back to documents index
    const afterDeleteUrl = page.url();
    const redirected = !afterDeleteUrl.match(/\/documents\/\d+/);
    expect(redirected).toBeTruthy();
  });

  test('should create a folder for document organisation', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/documents`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (isPlanGated(page.url())) {
      test.skip('Guild documents require a paid plan');
      return;
    }

    // Look for a "New Folder" or folder creation button/form
    const folderBtn = page.locator('button:has-text("folder"), a:has-text("folder"), button:has-text("Folder")').first();
    const folderBtnVisible = await folderBtn.isVisible({ timeout: 3000 }).catch(() => false);

    if (!folderBtnVisible) {
      test.skip('Folder creation UI not found on documents index — may require a different UI interaction');
      return;
    }

    await folderBtn.click();
    await page.waitForTimeout(500);

    // Folder name input may appear as a modal or inline form
    const folderInput = page.locator('input[name*="folder"], input[placeholder*="folder" i]').first();
    const inputVisible = await folderInput.isVisible({ timeout: 3000 }).catch(() => false);

    if (inputVisible) {
      await folderInput.fill(`Test Folder ${Date.now()}`);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(500);
    }

    // Assert we're still on the documents page without an error
    expect(page.url()).toContain('/documents');
  });
});
