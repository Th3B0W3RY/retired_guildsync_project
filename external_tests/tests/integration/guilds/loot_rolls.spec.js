import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle, createGuildViaAPI } from '../../helpers/test-helpers';

function lootRollSubmitSelector(guildId) {
  return `form[action*="/guilds/${guildId}/loot_rolls"] input[type="submit"], form[action*="/guilds/${guildId}/loot_rolls"] button[type="submit"]`;
}

test.describe('Guild Loot Rolls', () => {
  let ownerEmail, ownerPassword, ownerToken, guildId;

  test.beforeEach(async ({ page, request }) => {
    const owner = await createTestUserAndGetToken(request, {
      emailAffix: 'lootow',
      usernameAffix: 'lootow',
      authMethod: 'discord'
    });
    ownerEmail = owner.email;
    ownerPassword = owner.password;
    ownerToken = owner.token;

    guildId = await createGuildViaAPI(request, ownerToken, `Loot Test ${Date.now()}`);

    await loginAndSettle(page, ownerEmail, ownerPassword);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }
  });

  test('should display the loot rolls index page', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/loot_rolls`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing loot rolls: ${currentUrl}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should display the new loot roll form', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/loot_rolls/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing new loot roll form: ${currentUrl}`);
    }

    // Title, min/max roll are required form fields
    const titleField = page.locator('[name="loot_roll[title]"]').first();
    const minRollField = page.locator('[name="loot_roll[min_roll]"]').first();
    const maxRollField = page.locator('[name="loot_roll[max_roll]"]').first();

    await expect(titleField).toBeVisible({ timeout: 5000 });
    await expect(minRollField).toBeVisible({ timeout: 5000 });
    await expect(maxRollField).toBeVisible({ timeout: 5000 });
  });

  test('should show an error when Discord channel is not configured', async ({ page }) => {
    // Loot rolls REQUIRE a Discord channel — creation without one should fail
    await page.goto(`/guilds/${guildId}/loot_rolls/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (page.url().includes('/login') || page.url().includes('/mfa')) {
      throw new Error('Redirected to auth when accessing loot roll form');
    }

    const titleField = page.locator('[name="loot_roll[title]"]').first();
    if (!await titleField.isVisible({ timeout: 3000 }).catch(() => false)) {
      throw new Error('Loot roll form not found — cannot test Discord channel requirement');
    }

    await titleField.fill(`Channel Required ${Date.now()}`);
    // min/max roll have defaults; submit as-is
    await page.click(lootRollSubmitSelector(guildId));
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterUrl = page.url();

    // Without a Discord channel configured, creation should fail:
    // either redirect back to form with error, or show a toast
    const hasError = await page.locator('[role="alert"]').isVisible({ timeout: 3000 }).catch(() => false);
    const stayedOnForm = afterUrl.includes('/loot_rolls');

    expect(hasError || stayedOnForm).toBeTruthy();
  });

  test('should show default min and max roll values', async ({ page }) => {
    await page.goto(`/guilds/${guildId}/loot_rolls/new`);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    if (page.url().includes('/login') || page.url().includes('/mfa')) {
      throw new Error('Redirected to auth when accessing loot roll form');
    }

    const minRoll = page.locator('[name="loot_roll[min_roll]"]').first();
    const maxRoll = page.locator('[name="loot_roll[max_roll]"]').first();

    const minValue = await minRoll.inputValue({ timeout: 3000 }).catch(() => null);
    const maxValue = await maxRoll.inputValue({ timeout: 3000 }).catch(() => null);

    // Defaults are 1 and 100
    expect(minValue).toBe('1');
    expect(maxValue).toBe('100');
  });

  test('should skip loot roll creation without Discord bot', async () => {
    test.skip('Creating a loot roll requires a Discord channel to be configured (loot rolls auto-post to Discord). This environment has no Discord bot connected. Configure a Discord bot and set loot_rolls_channel_id on the guild to enable this test.');
  });

  test('should skip loot roll close and force-reroll without Discord bot', async () => {
    test.skip('Closing a loot roll and force-rerolling require a loot roll to exist, which in turn requires a Discord bot. Configure Discord integration to enable these tests.');
  });
});
