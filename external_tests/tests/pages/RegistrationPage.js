/**
 * Account creation entry Page Object Model.
 * The legacy /sign_up route redirects here.
 */

export class RegistrationPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    emailInput: 'input[name="email"]',
    usernameInput: 'input[name="user[username]"]',
    passwordInput: 'input[name="user[password]"]',
    passwordConfirmationInput: 'input[name="user[password_confirmation]"]',
    submitButton: 'input[type="submit"], button[type="submit"]',
    errorMessage: 'text=/invalid|error|required/i',
    planSelector: 'input[type="radio"][name*="plan"]'
  };

  // Navigation
  async goto() {
    await this.page.goto('/create_account');
  }

  // Actions
  async fillEmail(email) {
    await this.page.fill(this.selectors.emailInput, email);
  }

  async fillUsername(username) {
    await this.page.fill(this.selectors.usernameInput, username);
  }

  async fillPassword(password) {
    await this.page.fill(this.selectors.passwordInput, password);
  }

  async fillPasswordConfirmation(passwordConfirmation) {
    await this.page.fill(this.selectors.passwordConfirmationInput, passwordConfirmation);
  }

  async fillForm({ email, username, password, passwordConfirmation }) {
    await this.fillEmail(email);
    await this.fillUsername(username);
    await this.fillPassword(password);
    if (passwordConfirmation) {
      await this.fillPasswordConfirmation(passwordConfirmation);
    }
  }

  async selectPlan(planId) {
    if (planId) {
      await this.page.click(`input[value="${planId}"]`);
    }
  }

  async submit() {
    await this.page.click(this.selectors.submitButton);
  }

  async register({ email, username, password, passwordConfirmation, planId }) {
    await this.fillForm({ email, username, password, passwordConfirmation });
    await this.selectPlan(planId);
    await this.submit();
  }

  // Assertions
  async expectErrorMessage() {
    // Look for the flash alert div with red styling (similar to LoginPage)
    const alertLocator = this.page.locator('div.bg-red-900\\/50, div[class*="red-900"], div.border-red-700').first();
    const alertExists = await alertLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (alertExists) {
      await alertLocator.waitFor({ state: 'visible', timeout: 5000 });
      return alertLocator;
    }
    
    // Fallback: Look for error messages in list items (Rails validation errors)
    // Errors are often displayed in <ul> or <ol> lists
    const listErrorLocator = this.page.locator('ul li, ol li')
      .filter({ hasText: /error|invalid|required|match|taken|already|length|minimum|maximum/i })
      .first();
    const listErrorExists = await listErrorLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (listErrorExists) {
      await listErrorLocator.waitFor({ state: 'visible', timeout: 5000 });
      return listErrorLocator;
    }
    
    // Final fallback: Look for error text that's NOT in normal page elements
    // Exclude h1, labels, links, and instructional paragraphs
    const errorText = this.page.locator('text=/error|invalid|required|match|taken|already|length|minimum|maximum/i')
      .filter({ 
        hasNot: this.page.locator('h1, h2, label, a, p.text-theme-secondary, p.text-sm') 
      })
      .first();
    
    await errorText.waitFor({ state: 'visible', timeout: 5000 });
    return errorText;
  }
}
