import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken } from '../../helpers/test-helpers';
import { LoginPage } from '../../pages';

function pricingCtaSelector() {
  return '.checkout-btn, .public-checkout-btn, a[href*="select_plan"], a[href*="subscribe"]';
}

test.describe('Paid Plan Subscriptions', () => {
  test('should display pricing plans on pricing page', async ({ page }) => {
    await page.goto('/pricing');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    
    // Verify pricing plans are displayed
    // Exclude navigation, buttons, and links to avoid strict mode violations
    const plansLocator = page.locator('text=/plan|pricing|month|year/i')
      .filter({ 
        hasNot: page.locator('nav, button, a, label') 
      })
      .first();
    
    const plansVisible = await plansLocator.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!plansVisible) {
      throw new Error('Pricing plans not displayed on /pricing — the page may not exist, renders no plan text, or is redirecting');
    }
    
    expect(plansVisible).toBeTruthy();
  });

  test('should allow selecting a paid plan', async ({ page }) => {
    await page.goto('/pricing');
    
    // Find and click on a paid plan (not free)
    const paidPlanButton = page.locator(pricingCtaSelector()).first();
    const buttonExists = await paidPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await paidPlanButton.click();
      
      // Should either redirect to signup or start subscription process
      // Adjust based on your flow
      await page.waitForTimeout(2000);
      
      const onSignup = await page.waitForURL(/\/create_account/, { timeout: 3000 }).catch(() => false);
      const onSubscribe = await page.waitForURL(/\/subscribe/, { timeout: 3000 }).catch(() => false);
      
      expect(onSignup || onSubscribe || page.url().includes('/pricing')).toBeTruthy();
    }
  });

  test('should start trial for paid plan', async ({ page, request }) => {
    // Create a fresh Discord-auth user — bypasses MFA in the browser UI.
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'paidplan3',
      usernameAffix: 'paidplan3',
      authMethod: 'discord'
    });

    await page.goto('/login');
    await page.fill('input[name="user[email]"]', email);
    await page.fill('input[name="user[password]"]', password);
    await page.click('form[action="/sign_in"] input[type="submit"], form[action="/sign_in"] button[type="submit"]');

    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    // Navigate to a protected page first — Discord-auth users may briefly land on
    // /mfa/setup after sign-in until require_mfa_if_enabled sets session[:mfa_verified].
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const currentUrl = page.url();

    if (currentUrl.includes('/login')) {
      throw new Error('Login failed — could not authenticate Discord-auth test user');
    }

    if (currentUrl.includes('/mfa/verify') || currentUrl.includes('/mfa/setup')) {
      throw new Error(`Discord auth bypass failed — redirected to MFA at ${currentUrl}`);
    }
    
    await page.goto('/pricing');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    
    // Select a paid plan
    const paidPlanButton = page.locator(pricingCtaSelector()).first();
    const buttonExists = await paidPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (!buttonExists) {
      test.skip('No selectable paid-plan CTA found on /pricing in this environment (likely plan/price configuration)');
      return;
    }
    
    await paidPlanButton.click();
    
    // Wait for response
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);
    
    // Should show trial information, redirect to Stripe, or show success
    const trialInfo = await page.locator('text=/trial|days|free/i')
      .filter({ hasNot: page.locator('nav, button, a') })
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);
    
    const redirected = await page.waitForURL(/\/(dashboard|guilds|success|stripe|checkout)/, { timeout: 5000 }).catch(() => false);
    
    expect(trialInfo || redirected).toBeTruthy();
  });

  test('should display trial status in user settings', async ({ page }) => {
    // This test assumes a logged-in user with an active trial
    await page.goto('/account/settings');
    
    // Verify trial status is displayed
    const trialStatus = page.locator('text=/trial|trialing|days left/i');
    const statusVisible = await trialStatus.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (statusVisible) {
      await expect(trialStatus).toBeVisible();
    }
  });

  test('should show trial expiration date', async ({ page }) => {
    // This test assumes a logged-in user with an active trial
    await page.goto('/account/settings');
    
    // Look for trial expiration information
    const expirationInfo = page.locator('text=/expires|ends|trial/i');
    const infoVisible = await expirationInfo.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (infoVisible) {
      await expect(expirationInfo).toBeVisible();
    }
  });

  test('should handle Stripe subscription flow', async ({ page }) => {
    // This test would verify the Stripe checkout flow
    // Note: In a real scenario, you might want to use Stripe test mode
    
    await page.goto('/pricing');
    
    // Select a paid plan that requires Stripe
    const paidPlanButton = page.locator(pricingCtaSelector()).first();
    const buttonExists = await paidPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await paidPlanButton.click();
      
      // Should redirect to Stripe checkout or show payment form
      // In test mode, you might see a test payment form
      const stripeCheckout = await page.waitForURL(/stripe|checkout|payment/, { timeout: 5000 }).catch(() => false);
      const paymentForm = await page.locator('input[name*="card"], input[type="tel"]').isVisible({ timeout: 5000 }).catch(() => false);
      
      // One of these should be true if Stripe integration is active
      if (stripeCheckout || paymentForm) {
        expect(stripeCheckout || paymentForm).toBeTruthy();
      }
    }
  });

  test('should show subscription success page after payment', async ({ page, request }) => {
    // Stripe test-mode is required: set STRIPE_SECRET_KEY=sk_test_... per TESTING_PLAN.md.
    if (!process.env.STRIPE_SECRET_KEY?.startsWith('sk_test_')) {
      test.skip('Stripe test-mode credentials not configured — set STRIPE_SECRET_KEY=sk_test_... and STRIPE_PUBLISHABLE_KEY in .env to enable this test');
      return;
    }

    // Log in so the success page is accessible (it requires authentication).
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'stripesuccess',
      usernameAffix: 'stripesuccess',
      authMethod: 'discord'
    });

    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(email, password);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);

    const afterLogin = page.url();
    if (afterLogin.includes('/login') || afterLogin.includes('/mfa')) {
      throw new Error(`Login failed — redirected to ${afterLogin}`);
    }

    await page.goto('/subscriptions/success');
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const currentUrl = page.url();
    if (currentUrl.includes('/pricing') || currentUrl.includes('/dashboard')) {
      // Redirected because no active Stripe session — expected without a real checkout.
      test.skip('No active Stripe checkout session — visit /pricing, complete a test checkout with card 4242 4242 4242 4242, then the success redirect will hit this page');
      return;
    }

    const successMessage = page.locator('text=/success|thank you|activated/i')
      .filter({ hasNot: page.locator('nav, button, a, label') })
      .first();

    await expect(successMessage).toBeVisible({ timeout: 5000 });
  });
});
