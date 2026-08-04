import { test, expect } from '@playwright/test';

/**
 * Discord OAuth Tests
 * 
 * NOTE: Full Discord OAuth flow cannot be automated due to CAPTCHA requirements.
 * These tests verify that Discord OAuth buttons exist and can navigate to test mode
 * (if backend implements test mode bypass - see DISCORD_OAUTH_TESTING_RECOMMENDATIONS.md).
 * 
 * For full OAuth testing, backend must implement test mode bypass.
 */
test.describe('Discord OAuth', () => {
  
  test('should display Discord login button on login page', async ({ page }) => {
    // Navigate to login page
    await page.goto('/login');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    
    // Look for Discord OAuth button/link
    const discordButton = page.locator(
      'a:has-text("Discord"), ' +
      'button:has-text("Discord"), ' +
      'a:has-text("Sign in with Discord"), ' +
      'button:has-text("Sign in with Discord"), ' +
      'a[href*="discord"], ' +
      'a[href*="oauth"]'
    ).first();
    
    // Verify button exists (actual OAuth flow cannot be tested due to CAPTCHA)
    const buttonVisible = await discordButton.isVisible({ timeout: 5000 }).catch(() => false);
    expect(buttonVisible).toBeTruthy();
  });

  test('should route registration through email verification before OAuth choices', async ({ page }) => {
    await page.goto('/sign_up');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    await expect(page).toHaveURL(/\/create_account/);
    await expect(page.locator('input[name="email"]')).toBeVisible();
  });
});
