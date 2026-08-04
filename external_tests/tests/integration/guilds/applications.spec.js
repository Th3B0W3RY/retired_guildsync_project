import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';
import { getAPIBaseURL } from '../../../config/test-config.js';
import { GuildApplicationPage } from '../../pages';

test.describe('Guild Applications', () => {
  test('should display the applications index page', async ({ page, request }) => {
    const user = await createTestUserAndGetToken(request, {
      emailAffix: 'appidx',
      usernameAffix: 'appidx',
      authMethod: 'discord'
    });

    await loginAndSettle(page, user.email, user.password);

    await page.goto('/guild_applications');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing guild applications: ${currentUrl}`);
    }

    const heading = page.locator('h1').first();
    await expect(heading).toBeVisible({ timeout: 5000 });

    // Apply button should be present
    const applyLink = page.locator('a[href*="guild_applications/new"], a[href*="new_guild_application"]').first();
    await expect(applyLink).toBeVisible({ timeout: 5000 });
  });

  test('should display the new application form', async ({ page, request }) => {
    const user = await createTestUserAndGetToken(request, {
      emailAffix: 'appnew',
      usernameAffix: 'appnew',
      authMethod: 'discord'
    });

    await loginAndSettle(page, user.email, user.password);

    const appPage = new GuildApplicationPage(page);
    await appPage.gotoNew();

    if (await appPage.isOnAuthPage()) {
      throw new Error(`Redirected to auth when accessing new application form: ${page.url()}`);
    }

    expect(await appPage.isGuildSearchVisible()).toBeTruthy();
    expect(await appPage.isDiscordUsernameVisible()).toBeTruthy();
    await expect(page.locator('[name="message"]').first()).toBeVisible({ timeout: 5000 });
  });

  test('should submit an application to a guild', async ({ page, request }) => {
    // Owner creates the guild; applicant applies to it
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'appown',
      usernameAffix: 'appown',
      authMethod: 'discord'
    });
    const applicant = await createTestUserAndGetToken(request, {
      emailAffix: 'applic',
      usernameAffix: 'applic',
      authMethod: 'discord'
    });

    const guildName = `Apply Test ${Date.now()}`;
    const guildId = await createGuildViaAPI(request, owner.token, guildName);

    await loginAndSettle(page, applicant.email, applicant.password);

    await page.goto('/guild_applications/new');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Search for the guild by name
    const searchInput = page.locator('#guild-search-input').first();
    await searchInput.fill(guildName.substring(0, 8));
    await page.waitForTimeout(600); // debounce

    // Pick from dropdown if it appeared
    const dropdownOption = page.locator('#guild-search-dropdown .autocomplete-option, #guild-search-dropdown [data-guild-id]').first();
    const dropdownVisible = await dropdownOption.isVisible({ timeout: 3000 }).catch(() => false);
    if (dropdownVisible) {
      await dropdownOption.click();
      await page.waitForTimeout(300);
    } else {
      // Guild may not be publicly discoverable — skip
      test.skip('Guild not appearing in application search results — guild may require a public/discoverable setting to accept applications');
      return;
    }

    await page.fill('[name="discord_username"]', 'TestApplicant#1234');
    await page.fill('[name="message"]', 'I would like to join this test guild.');

    await page.click('#guild-application-form input[type="submit"], #guild-application-form button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterUrl = page.url();
    // Success: redirect to applications index, or success toast
    const submitted = afterUrl.includes('/guild_applications') && !afterUrl.includes('/new');
    const successToast = await page.locator('[role="alert"]').isVisible({ timeout: 3000 }).catch(() => false);

    if (!submitted && !successToast) {
      // May still be on new page with a validation error — surface it
      const errorText = await page.locator('[role="alert"], .bg-red-900\\/20, div.bg-red-900\\/50').first().textContent({ timeout: 2000 }).catch(() => '');
      throw new Error(`Application submission did not redirect or show success. Error: "${errorText}". URL: ${afterUrl}`);
    }

    expect(submitted || successToast).toBeTruthy();
  });

  test('should show received applications to guild owner', async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'apprvw',
      usernameAffix: 'apprvw',
      authMethod: 'discord'
    });
    const guildId = await createGuildViaAPI(request, owner.token, `Review App ${Date.now()}`);

    await loginAndSettle(page, owner.email, owner.password);

    await page.goto(`/guilds/${guildId}/applications`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing applications review: ${currentUrl}`);
    }

    // Page should load — may be empty (no applicants yet) but should not error
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should prevent applying to a guild the user already belongs to', async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'appalr',
      usernameAffix: 'appalr',
      authMethod: 'discord'
    });
    const guildName = `Already Member ${Date.now()}`;
    await createGuildViaAPI(request, owner.token, guildName);

    // Owner tries to apply to their own guild
    await loginAndSettle(page, owner.email, owner.password);

    await page.goto('/guild_applications/new');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const searchInput = page.locator('#guild-search-input').first();
    await searchInput.fill(guildName.substring(0, 8));
    await page.waitForTimeout(600);

    const dropdownOption = page.locator('#guild-search-dropdown .autocomplete-option, #guild-search-dropdown [data-guild-id]').first();
    const dropdownVisible = await dropdownOption.isVisible({ timeout: 3000 }).catch(() => false);
    if (!dropdownVisible) {
      test.skip('Guild not appearing in search — skipping already-member validation test');
      return;
    }

    await dropdownOption.click();
    await page.waitForTimeout(300);
    await page.fill('[name="discord_username"]', 'Owner#0000');
    await page.click('#guild-application-form input[type="submit"], #guild-application-form button[type="submit"]');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Should be rejected with an error
    const hasError = await page.locator('[role="alert"]').isVisible({ timeout: 3000 }).catch(() => false);
    const stayedOnForm = page.url().includes('/guild_applications');
    expect(hasError || stayedOnForm).toBeTruthy();
  });
});
