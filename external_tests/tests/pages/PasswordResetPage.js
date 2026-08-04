/**
 * Password Reset Page Object Model
 * Encapsulates all interactions with the password reset page
 */

export class PasswordResetPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    emailInput: '#password_reset_email',
    submitButton: '.email-reset-form input[type="submit"], .email-reset-form button[type="submit"]',
    successMessage: 'text=/sent|email|check|instructions/i',
    errorMessage: 'text=/email|invalid|format/i'
  };

  // Navigation
  async goto() {
    await this.page.goto('/password/new');
  }

  // Actions
  async fillEmail(email) {
    await this.page.fill(this.selectors.emailInput, email);
  }

  async submit() {
    await this.page.click(this.selectors.submitButton);
  }

  async requestReset(email) {
    await this.fillEmail(email);
    await this.submit();
  }

  // Assertions
  async expectEmailField() {
    const emailField = this.page.locator(this.selectors.emailInput).first();
    await emailField.waitFor({ state: 'visible', timeout: 5000 });
    return emailField;
  }

  async expectSuccessMessage() {
    // Prioritize flash alert divs (success messages are typically in green/blue alert divs)
    const alertLocator = this.page.locator('div.bg-green-900\\/50, div[class*="green-900"], div.bg-blue-900\\/50, div[class*="blue-900"], div.border-green-700, div.border-blue-700').first();
    const alertExists = await alertLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (alertExists) {
      await alertLocator.waitFor({ state: 'visible', timeout: 5000 });
      return alertLocator;
    }
    
    // Fallback: Look for success text that's NOT in normal page elements
    // Exclude h1, labels, links, instructional paragraphs, and buttons
    const successText = this.page.locator('text=/sent|email|check|instructions/i')
      .filter({ 
        hasNot: this.page.locator('h1, label, a, p.text-theme-secondary, p.text-sm, button, input') 
      })
      .first();
    
    await successText.waitFor({ state: 'visible', timeout: 5000 });
    return successText;
  }

  async expectErrorMessage() {
    // Toast alerts (flash messages after redirect) use role="alert"
    const toastLocator = this.page.locator('[role="alert"]').first();
    const toastExists = await toastLocator.isVisible({ timeout: 2000 }).catch(() => false);
    if (toastExists) {
      return toastLocator;
    }

    // Inline form errors (re-rendered edit template) use bg-red-900/50
    const inlineLocator = this.page.locator('div.bg-red-900\\/50, div[class*="red-900"], div.border-red-700').first();
    const inlineExists = await inlineLocator.isVisible({ timeout: 2000 }).catch(() => false);
    if (inlineExists) {
      return inlineLocator;
    }

    // Fallback: error text not in structural page elements
    const errorText = this.page.locator('text=/email|invalid|format|error/i')
      .filter({
        hasNot: this.page.locator('h1, label, a, p.text-theme-secondary, p.text-sm, button, input')
      })
      .first();

    await errorText.waitFor({ state: 'visible', timeout: 5000 });
    return errorText;
  }
}
