import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle } from '../../helpers/test-helpers';
import { AccountSettingsPage } from '../../pages';

// Tests for /account/settings:
// - Page renders with heading
// - Password change link is present
// - Language selector (select#preferred_locale) is present with locale options
// - Locale update via PATCH /settings/locale redirects back without error
// - Unauthenticated users are redirected to /login

test.describe('Account Settings', () => {
  let email, password;

  test.beforeEach(async ({ page, request }) => {
    const user = await createTestUserAndGetToken(request, {
      emailAffix: 'acctsett',
      usernameAffix: 'acctsett',
      authMethod: 'discord'
    });
    email = user.email;
    password = user.password;

    await loginAndSettle(page, email, password);
  });

  test('should redirect unauthenticated users to login', async ({ page }) => {
    await page.context().clearCookies();

    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    expect(settingsPage.isOnAuthPage()).toBeTruthy();
  });

  test('should render the account settings page with heading', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    if (settingsPage.isOnAuthPage()) {
      throw new Error(`Redirected to auth on account settings: ${page.url()}`);
    }

    expect(await settingsPage.isHeadingVisible()).toBeTruthy();
  });

  test('should display the password change section', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    expect(await settingsPage.isPasswordLinkVisible()).toBeTruthy();
  });

  test('should display the language preference selector', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    expect(await settingsPage.isLocaleSelectorVisible()).toBeTruthy();

    const optionCount = await settingsPage.getLocaleOptionCount();
    expect(optionCount).toBeGreaterThan(1);
  });

  test('should update locale and redirect back to account settings', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    if (!(await settingsPage.isLocaleSelectorVisible())) {
      throw new Error('Language select not found on /account/settings');
    }

    await settingsPage.selectLocale('de');
    await settingsPage.submitLocaleForm();

    expect(settingsPage.isServerError()).toBeFalsy();
    expect(settingsPage.isOnSettingsPage()).toBeTruthy();
  });

  test('should display the MFA section', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    expect(await settingsPage.isMfaSectionVisible()).toBeTruthy();
  });

  test('should display the Discord connection section', async ({ page }) => {
    const settingsPage = new AccountSettingsPage(page);
    await settingsPage.goto();

    expect(await settingsPage.isDiscordSectionVisible()).toBeTruthy();
  });
});
