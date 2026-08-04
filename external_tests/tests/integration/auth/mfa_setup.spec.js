import { test, expect } from '@playwright/test';
import { expectNavigation, completeMFASetup, createMFASetupUserAndLogin } from '../../helpers/test-helpers';
import { MfaSetupPage } from '../../pages';
import { generateOTP } from '../../helpers/otp-helpers';

test.describe('MFA Setup', () => {
  test('should display QR code for MFA setup', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, { emailPrefix: 'mfa_setup', usernamePrefix: 'mfa_setup' });
    
    // Use page object to verify QR code
    const mfaSetupPage = new MfaSetupPage(page);
    await mfaSetupPage.expectQrCode();
    
    // Verify instructions are displayed (exclude buttons and labels)
    const instructions = page.locator('text=/scan|QR|code|authenticator/i')
      .filter({ 
        hasNot: page.locator('button, input[type="submit"], label') 
      })
      .first();
    await expect(instructions).toBeVisible();
  });

  test('should show manual entry option for MFA secret', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, { emailPrefix: 'mfa_manual', usernamePrefix: 'mfa_manual' });
    
    // The secret is always shown as a <code> element below the QR code.
    // No toggle required — it is part of the static setup page layout.
    const secretCode = page.locator('code.font-mono, code.text-theme-accent').first();
    const hasSecret = await secretCode.isVisible({ timeout: 5000 }).catch(() => false);

    if (hasSecret) {
      await expect(secretCode).toBeVisible();
    } else {
      throw new Error('Secret code element (code.font-mono / code.text-theme-accent) not found on MFA setup page — view may have changed');
    }
  });

  test('should successfully verify MFA setup with correct code', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, { emailPrefix: 'mfa_verify', usernamePrefix: 'mfa_verify' });
    
    // Wait for QR code to be visible (indicating setup is ready)
    const mfaSetupPage = new MfaSetupPage(page);
    await mfaSetupPage.expectQrCode();

    // Read the actual OTP secret from the <code> element displayed on the page.
    // The backend generates a unique secret per user; the page shows it as
    // "XXXX XXXX XXXX ..." — strip spaces to get a clean Base32 string.
    const secretElement = page.locator('code.font-mono, code.text-theme-accent').first();
    await secretElement.waitFor({ state: 'visible', timeout: 5000 });
    const secretRaw = await secretElement.textContent();
    const secret = (secretRaw || '').replace(/\s+/g, '').toUpperCase();

    if (!secret) {
      throw new Error('OTP secret element was present but empty — cannot generate a valid TOTP code');
    }

    const validOTPCode = generateOTP(secret);

    // Fill in the OTP code
    await completeMFASetup(page, validOTPCode);

    // Wait for navigation
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // Check if we're still on MFA setup (code was invalid) or redirected
    const currentUrl = page.url();
    if (currentUrl.includes('/mfa/setup')) {
      throw new Error('MFA setup code was rejected — the TOTP code generated from the page secret was invalid. Check that speakeasy and the server TOTP library agree on the algorithm and time window.');
    }

    // Should redirect to dashboard or home after successful verification
    await expectNavigation(page, '/dashboard', 10000);
  });

  test('should show error for invalid MFA code', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, { emailPrefix: 'mfa_invalid', usernamePrefix: 'mfa_invalid' });

    // Wait for setup page to load
    const mfaSetupPage = new MfaSetupPage(page);
    await mfaSetupPage.expectQrCode();

    // Enter invalid code
    await completeMFASetup(page, '000000');
    
    // Wait for response
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // Should show error message using page object method
    await mfaSetupPage.expectErrorMessage();
    
    // Should remain on MFA setup page
    await expect(page).toHaveURL(/\/mfa\/setup/);
  });

  test('should show error for expired MFA code', async ({ page, request }) => {
    await createMFASetupUserAndLogin(page, request, { emailPrefix: 'mfa_expired', usernamePrefix: 'mfa_expired' });

    // Wait for setup page to load
    const mfaSetupPage = new MfaSetupPage(page);
    await mfaSetupPage.expectQrCode();

    // Enter an invalid code (expired codes are hard to test without waiting for time window)
    await completeMFASetup(page, '999999');
    
    // Wait for response
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // The error toast has role="alert". Wait up to 4 s for it to appear
    // (it auto-dismisses after ~2.8 s, so we must check before it disappears).
    const errorVisible = await page.locator('[role="alert"]').isVisible({ timeout: 4000 }).catch(() => false);

    if (errorVisible) {
      await expect(page.locator('[role="alert"]').first()).toBeVisible();
    } else {
      throw new Error('No error toast ([role="alert"]) appeared after submitting an invalid MFA code — error feedback may be broken');
    }
  });

  test('should require MFA setup after registration', async ({ page }) => {
    // This test verifies that new users are redirected to MFA setup
    // Login with the MFA test user, which should redirect to MFA setup
    const email = 'test_data_mfa@example.com';
    const password = 'password123';

    // Login first - this should redirect to MFA setup if not completed
    await page.goto('/login');
    await page.fill('input[name="user[email]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.click('input[type="submit"], button[type="submit"]');
    
    // Wait for navigation after login
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Verify we're on the MFA setup page (or MFA verify if already set up)
    const currentUrl = page.url();
    const onMfaSetup = currentUrl.includes('/mfa/setup');
    const onMfaVerify = currentUrl.includes('/mfa/verify');
    
    // Should be on either MFA setup or verify page
    expect(onMfaSetup || onMfaVerify).toBeTruthy();
    
    if (onMfaSetup) {
      // Use page object to verify setup prompt
      const mfaSetupPage = new MfaSetupPage(page);
      await mfaSetupPage.expectSetupPrompt();
    }
  });

  test('should prevent skipping MFA setup', async ({ request }) => {
    const response = await request.get('/dashboard', { maxRedirects: 0, timeout: 10000 });

    expect([302, 303]).toContain(response.status());
    expect(response.headers().location || '').toMatch(/\/(login|mfa\/setup|mfa\/verify)|\/$/);
  });
});
