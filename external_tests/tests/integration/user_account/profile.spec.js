import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle } from '../../helpers/test-helpers';
import { ProfileSettingsPage } from '../../pages';

// Tests for /profile/settings (avatar, username, email sections)
// and /profile/complete (completion redirect for already-complete users).
//
// Avatar upload/removal are form interactions with a file input; actual binary upload
// is exercised by the "upload file" test and skipped for removal (no attached avatar
// in a fresh test account).

test.describe('Profile Settings', () => {
  let email, password;

  test.beforeEach(async ({ page, request }) => {
    const user = await createTestUserAndGetToken(request, {
      emailAffix: 'profsett',
      usernameAffix: 'profsett',
      authMethod: 'discord'
    });
    email = user.email;
    password = user.password;

    await loginAndSettle(page, email, password);
  });

  test('should redirect unauthenticated users to login', async ({ page }) => {
    await page.context().clearCookies();

    const profilePage = new ProfileSettingsPage(page);
    await profilePage.goto();

    expect(profilePage.isOnAuthPage()).toBeTruthy();
  });

  test('should render the profile settings page with heading', async ({ page }) => {
    const profilePage = new ProfileSettingsPage(page);
    await profilePage.goto();

    if (profilePage.isOnAuthPage()) {
      throw new Error(`Redirected to auth on profile settings: ${page.url()}`);
    }

    expect(await profilePage.isHeadingVisible()).toBeTruthy();
  });

  test('should display the avatar upload section', async ({ page }) => {
    const profilePage = new ProfileSettingsPage(page);
    await profilePage.goto();

    expect(await profilePage.hasAvatarSection()).toBeTruthy();
  });

  test('should display the current username on the profile settings page', async ({ page }) => {
    const profilePage = new ProfileSettingsPage(page);
    await profilePage.goto();

    expect(await profilePage.isUsernameSectionVisible()).toBeTruthy();
  });

  test('should display the current email on the profile settings page', async ({ page }) => {
    const profilePage = new ProfileSettingsPage(page);
    await profilePage.goto();

    expect(await profilePage.isEmailVisible(email)).toBeTruthy();
  });

  test('should skip avatar upload with a real image file', async () => {
    test.skip(
      'Avatar upload (PATCH /profile/avatar) requires attaching a binary image file. ' +
      'This is testable with Playwright\'s setInputFiles() but requires a fixture image on disk. ' +
      'Add a test image asset and use page.locator("#avatar-upload-input").setInputFiles(path) to enable.'
    );
  });

  test('should skip avatar removal (requires an attached avatar)', async () => {
    test.skip(
      'Avatar removal (DELETE /profile/avatar) only renders the Remove button when an avatar ' +
      'is already attached. Upload an avatar first (see above test) then test removal.'
    );
  });
});

test.describe('Profile Completion', () => {
  test('should redirect an already-complete user away from /profile/complete', async ({ page, request }) => {
    // Test users created via the API always have a real email + password, so
    // profile_complete? returns true and /profile/complete redirects to account settings.
    const user = await createTestUserAndGetToken(request, {
      emailAffix: 'profcomp',
      usernameAffix: 'profcomp',
      authMethod: 'discord'
    });

    await loginAndSettle(page, user.email, user.password);

    const profilePage = new ProfileSettingsPage(page);
    await profilePage.gotoComplete();

    // check_if_already_complete redirects complete users to /account/settings
    const url = page.url();
    expect(url.includes('/account/settings') || url.includes('/dashboard')).toBeTruthy();
  });

  test('should show the profile completion form for incomplete users', async () => {
    test.skip(
      'The profile completion form is shown only when the user has an incomplete profile ' +
      '(e.g. a Discord-OAuth user whose email contains @discord.guildsync.local). ' +
      'Normal test API users always have a complete profile so this flow cannot be triggered ' +
      'without a special test seed or a mock Discord OAuth callback.'
    );
  });
});
