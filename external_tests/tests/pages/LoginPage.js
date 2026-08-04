/**
 * Login Page Object Model
 * Encapsulates all interactions with the login page
 */

export class LoginPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    emailInput: 'input[name="user[email]"]',
    passwordInput: 'input[name="user[password]"]',
    submitButton: 'input[type="submit"], button[type="submit"]',
    errorMessage: 'text=/invalid|email|password|credentials/i',
    mfaPrompt: 'text=/MFA|Two-Factor|Verify/i'
  };

  // Navigation
  async goto() {
    await this.page.goto('/login');
  }

  // Actions
  async fillEmail(email) {
    await this.page.fill(this.selectors.emailInput, email);
  }

  async fillPassword(password) {
    await this.page.fill(this.selectors.passwordInput, password);
  }

  async fillForm({ email, password }) {
    await this.fillEmail(email);
    await this.fillPassword(password);
  }

  async submit() {
    await this.page.click(this.selectors.submitButton);
  }

  /**
   * Simple login - fills form and submits without waiting or validation
   * 
   * Use this method when:
   * - You need low-level control over the login flow
   * - You want to handle MFA verification yourself (e.g., in MFA tests)
   * - You want to test specific login behaviors or error handling
   * - You don't need automatic error detection or MFA validation
   * 
   * Example: MFA verification tests that expect MFA and handle it themselves
   * 
   * @param {string} email - User email
   * @param {string} password - User password
   */
  async login(email, password) {
    await this.fillForm({ email, password });
    await this.submit();
  }

  /**
   * Login and wait for successful authentication with validation
   * 
   * Use this method when:
   * - You just need to log in and continue with your test
   * - You want automatic error detection and helpful error messages
   * - You want to ensure login succeeded before proceeding
   * - You don't need to handle MFA flow yourself (use allowMFA option if MFA is expected)
   * 
   * This method will:
   * - Navigate to login page
   * - Fill and submit the form
   * - Wait for response and validate success
   * - Throw descriptive errors if login fails
   * - Optionally allow MFA (if allowMFA: true) or throw error if MFA required
   * 
   * Example: Tests that need authenticated user but don't test login itself
   * 
   * @param {string} email - User email
   * @param {string} password - User password
   * @param {Object} options - Options
   * @param {boolean} options.allowMFA - If true, allows MFA verification (default: false). 
   *                                     When false, throws error if MFA is required.
   * @returns {Promise<string>} The final URL after login (for further checks if needed)
   */
  async loginAndWaitForSuccess(email, password, options = {}) {
    const { allowMFA = false } = options;
    
    await this.goto();
    await this.login(email, password);
    
    // Wait for response - could be MFA verification, dashboard, or error
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await this.page.waitForTimeout(1000);
    
    // Check current URL
    const currentUrl = this.page.url();
    
    // If still on login page, login failed
    if (currentUrl.includes('/login')) {
      // Check if there's a visible error message
      const hasError = await this.page.locator('div.bg-red-900\\/50, div[class*="red-900"], div.border-red-700').isVisible({ timeout: 2000 }).catch(() => false);
      if (!hasError) {
        // No error shown (security feature) - user might not exist
        throw new Error('Login failed - test user may not exist or credentials are incorrect. Run: npm run test:verify');
      }
      throw new Error('Login failed - check test user setup');
    }
    
    // Check if MFA is required
    if ((currentUrl.includes('/mfa/verify') || currentUrl.includes('/mfa/setup')) && !allowMFA) {
      throw new Error('MFA verification required - test user should have auth_method: "discord" to bypass MFA. Current URL: ' + currentUrl);
    }
    
    // Login successful - session should be established
    return currentUrl;
  }

  // Assertions
  async expectErrorMessage() {
    // Look for the flash alert div with red styling (similar to MFA verification page)
    // This is the most specific selector for error messages
    const alertLocator = this.page.locator('div.bg-red-900\\/50, div[class*="red-900"], div.border-red-700').first();
    const alertExists = await alertLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (alertExists) {
      await alertLocator.waitFor({ state: 'visible', timeout: 5000 });
      return alertLocator;
    }
    
    // Fallback: Look for error text that's NOT in normal page elements
    // Exclude h1, labels, links, and instructional paragraphs
    const errorText = this.page.locator('text=/invalid|incorrect|wrong|error|credentials/i')
      .filter({ 
        hasNot: this.page.locator('h1, label, a, p.text-theme-secondary, p.text-sm') 
      })
      .first();
    
    await errorText.waitFor({ state: 'visible', timeout: 5000 });
    return errorText;
  }

  async expectMfaPrompt() {
    const mfaLocator = this.page.locator(this.selectors.mfaPrompt);
    await mfaLocator.waitFor({ state: 'visible', timeout: 5000 });
    return mfaLocator;
  }
}
