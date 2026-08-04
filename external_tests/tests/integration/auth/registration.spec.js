import { test, expect } from '@playwright/test';
import { generateTestEmail } from '../../helpers/test-helpers';

test.describe('User Registration', () => {
  test('routes legacy sign-up to the email verification flow', async ({ page }) => {
    await page.goto('/sign_up');

    await expect(page).toHaveURL(/\/create_account/);
    await expect(page.locator('input[name="email"]')).toBeVisible();
  });

  test('starts account creation for a valid email', async ({ page }) => {
    await page.goto('/create_account');
    await page.fill('input[name="email"]', generateTestEmail('register'));
    await page.click('input[type="submit"], button[type="submit"]');

    await expect(page).toHaveURL(/\/create_account\/sent/);
    await expect(page.locator('body')).toContainText(/check|email|sent|verify/i);
  });

  test('uses browser validation for invalid email format', async ({ page }) => {
    await page.goto('/create_account');
    const emailInput = page.locator('input[name="email"]');

    await emailInput.fill('invalid-email');
    const isInvalid = await emailInput.evaluate((el) => el.validity.valid === false);

    expect(isInvalid).toBeTruthy();
  });

  test('shows an error for an already registered email', async ({ page }) => {
    await page.goto('/create_account');
    await page.fill('input[name="email"]', 'test_data@example.com');
    await page.click('input[type="submit"], button[type="submit"]');

    await expect(page).toHaveURL(/\/create_account/);
    await expect(page.locator('body')).toContainText(/already|taken|registered/i);
  });
});
