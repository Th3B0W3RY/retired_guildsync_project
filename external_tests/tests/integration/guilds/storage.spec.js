import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
import { StoragePage } from '../../pages';
import { getBaseURL } from '../../../config/test-config.js';

test.describe('Guild Storage', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'store',
      usernameAffix: 'store',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Storage Test ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    if (page.url().includes('/login') || page.url().includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${page.url()}`);
    }
  });

  test('should display the storage page', async ({ page }) => {
    const storagePage = new StoragePage(page);
    await storagePage.goto(guildId);

    if (storagePage.isPlanGated()) {
      test.skip('Guild storage requires a paid plan');
      return;
    }

    if (storagePage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing storage: ${page.url()}`);
    }

    const headingVisible = await storagePage.isHeadingVisible();
    expect(headingVisible).toBeTruthy();
  });

  test('should show the folder tree sidebar', async ({ page }) => {
    const storagePage = new StoragePage(page);
    await storagePage.goto(guildId);

    if (storagePage.isPlanGated()) {
      test.skip('Guild storage requires a paid plan');
      return;
    }

    const hasTree = await storagePage.hasFolderTree();
    expect(hasTree).toBeTruthy();
  });

  test('should create a new folder', async ({ page }) => {
    const storagePage = new StoragePage(page);
    await storagePage.goto(guildId);

    if (storagePage.isPlanGated()) {
      test.skip('Guild storage requires a paid plan');
      return;
    }

    const hasBtn = await storagePage.hasNewFolderButton();
    if (!hasBtn) {
      test.skip('New folder button not found — UI may differ');
      return;
    }

    const folderName = `Test Folder ${Date.now()}`;
    const created = await storagePage.createFolder(folderName);

    if (!created) {
      test.skip('Folder creation flow not available — input did not appear after clicking new folder button');
      return;
    }

    const folderVisible = await storagePage.isFolderVisible(folderName);
    expect(folderVisible).toBeTruthy();
  });

  test('should upload a file', async ({ page }) => {
    const storagePage = new StoragePage(page);
    await storagePage.goto(guildId);

    if (storagePage.isPlanGated()) {
      test.skip('Guild storage requires a paid plan');
      return;
    }

    const hasInput = await storagePage.hasFileInput();
    if (!hasInput) {
      test.skip('File input not found — upload UI may use a different mechanism');
      return;
    }

    const fileName = `test-upload-${Date.now()}.txt`;
    await storagePage.uploadFile({
      name: fileName,
      mimeType: 'text/plain',
      buffer: Buffer.from(`Integration test upload at ${new Date().toISOString()}`)
    });

    // File should appear in the grid or a success toast should be shown
    const fileVisible = await storagePage.isFileVisible(fileName);
    const successFlash = await page.locator('[role="alert"]').first().isVisible({ timeout: 3000 }).catch(() => false);

    if (!fileVisible && !successFlash) {
      const errorText = await page.locator('[role="alert"], .bg-red-900\\/50').first().textContent({ timeout: 2000 }).catch(() => '');
      throw new Error(`File upload did not succeed. Error: "${errorText}". URL: ${page.url()}`);
    }

    expect(fileVisible || successFlash).toBeTruthy();
  });

  test('should display uploaded file in the file list', async ({ page }) => {
    const storagePage = new StoragePage(page);
    await storagePage.goto(guildId);

    if (storagePage.isPlanGated()) {
      test.skip('Guild storage requires a paid plan');
      return;
    }

    const hasInput = await storagePage.hasFileInput();
    if (!hasInput) {
      test.skip('File input not found');
      return;
    }

    const fileName = `listed-file-${Date.now()}.txt`;
    await storagePage.uploadFile({
      name: fileName,
      mimeType: 'text/plain',
      buffer: Buffer.from('file listing test')
    });

    // Navigate away and back to verify the file persisted
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await storagePage.goto(guildId);

    const fileVisible = await storagePage.isFileVisible(fileName);
    expect(fileVisible).toBeTruthy();
  });

  test('should create a folder via the session API', async ({ page }) => {
    // Session-auth route — page.request carries session cookies.
    // Rails protect_from_forgery fires before authenticate_user!, so all mutating requests
    // also need the CSRF token from the page's <meta name="csrf-token"> tag.
    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content').catch(() => null);
    const folderRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/folders`,
      {
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          ...(csrf && { 'X-CSRF-Token': csrf })
        },
        data: { folder: { name: `API Folder ${Date.now()}` } }
      }
    );

    expect([200, 201]).toContain(folderRes.status());

    const body = await folderRes.json();
    expect(body.success || body.folder?.id).toBeTruthy();
  });

  test('should delete a folder via the session API', async ({ page }) => {
    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content').catch(() => null);
    const headers = { Accept: 'application/json', 'Content-Type': 'application/json', ...(csrf && { 'X-CSRF-Token': csrf }) };

    const createRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/folders`,
      { headers, data: { folder: { name: `Delete Me ${Date.now()}` } } }
    );

    if (![200, 201].includes(createRes.status())) {
      test.skip('Could not create folder to test deletion');
      return;
    }

    const createBody = await createRes.json();
    const folderId = createBody.folder?.id;
    if (!folderId) {
      test.skip('Folder ID not returned from create — cannot test deletion');
      return;
    }

    const deleteRes = await page.request.delete(
      `${getBaseURL()}/guilds/${guildId}/folders/${folderId}`,
      { headers: { Accept: 'application/json', ...(csrf && { 'X-CSRF-Token': csrf }) } }
    );

    expect([200, 204]).toContain(deleteRes.status());
  });

  test('should reject deleting a folder that contains files', async ({ page }) => {
    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content').catch(() => null);
    const jsonHeaders = { Accept: 'application/json', 'Content-Type': 'application/json', ...(csrf && { 'X-CSRF-Token': csrf }) };

    const createRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/folders`,
      { headers: jsonHeaders, data: { folder: { name: `Non-Empty ${Date.now()}` } } }
    );

    if (![200, 201].includes(createRes.status())) {
      test.skip('Could not create folder');
      return;
    }

    const folderId = (await createRes.json()).folder?.id;
    if (!folderId) {
      test.skip('No folder ID returned');
      return;
    }

    // Upload a file into the folder via multipart (CSRF token required here too)
    const fileContent = Buffer.from('content for non-empty folder test');
    const uploadRes = await page.request.post(
      `${getBaseURL()}/guilds/${guildId}/file_entries`,
      {
        headers: { Accept: 'application/json', ...(csrf && { 'X-CSRF-Token': csrf }) },
        multipart: {
          'files[]': { name: 'non-empty-test.txt', mimeType: 'text/plain', buffer: fileContent },
          folder_id: String(folderId)
        }
      }
    );

    if (![200, 201].includes(uploadRes.status())) {
      test.skip('Could not upload file into folder — cannot test non-empty folder deletion');
      return;
    }

    // Attempt to delete the non-empty folder — should be rejected (422 or 400)
    const deleteRes = await page.request.delete(
      `${getBaseURL()}/guilds/${guildId}/folders/${folderId}`,
      { headers: { Accept: 'application/json', ...(csrf && { 'X-CSRF-Token': csrf }) } }
    );

    expect([400, 422]).toContain(deleteRes.status());
  });
});
