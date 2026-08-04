/**
 * MFA Verification Page Object Model
 * Encapsulates all interactions with the MFA verification page
 */

export class MfaVerificationPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    otpInput: 'input[name="code"], input[name="otp_code"], input[name="mfa_code"], input[type="text"][placeholder*="code" i], input[type="text"][placeholder*="OTP" i]',
    submitButton: 'input[type="submit"], button:has-text("Verify"), button:has-text("Submit")',
    // Error message is in a flash alert div with specific classes
    errorMessage: '.bg-red-900\\/50, .border-red-700, [class*="red"], text=/invalid|incorrect|wrong|error/i',
    errorAlert: 'div.bg-red-900\\/50, div[class*="red-900"], div:has-text(/invalid|incorrect|wrong|error/i)',
    mfaPrompt: 'h1:has-text("Verify Your Identity"), text=/Verify Your Identity|Authentication Code|authenticator app/i',
    heading: 'h1:has-text("Verify Your Identity")',
    instructions: 'text=/Enter the.*digit.*code|authenticator app/i'
  };

  // Navigation
  async goto() {
    await this.page.goto('/mfa/verify');
  }

  // Actions
  async fillOtpCode(code) {
    // Try the most specific selector first (name="code")
    const otpInput = this.page.locator(this.selectors.otpInput).first();
    await otpInput.waitFor({ state: 'visible', timeout: 5000 });
    await otpInput.fill(code);
  }

  async submit() {
    const submitButton = this.page.locator(this.selectors.submitButton).first();
    await submitButton.click();
  }

  async verify(code) {
    await this.fillOtpCode(code);
    await this.submit();
  }

  // Assertions
  async expectErrorMessage() {
    // Look for the flash alert div with red styling (from ERB: bg-red-900/50 border-red-700)
    // This is the most specific selector for error messages
    const alertLocator = this.page.locator('div.bg-red-900\\/50, div[class*="red-900"], div.border-red-700').first();
    const alertExists = await alertLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (alertExists) {
      await alertLocator.waitFor({ state: 'visible', timeout: 5000 });
      return alertLocator;
    }
    
    // Fallback: Look for error text that's NOT in normal page elements
    // Exclude h1, labels, and instructional paragraphs
    const errorText = this.page.locator('text=/invalid|incorrect|wrong|error/i')
      .filter({ 
        hasNot: this.page.locator('h1, label, p.text-theme-secondary, p.text-sm') 
      })
      .first();
    
    await errorText.waitFor({ state: 'visible', timeout: 5000 });
    return errorText;
  }

  async expectMfaPrompt() {
    // Check for the heading first (most reliable)
    const headingLocator = this.page.locator(this.selectors.heading);
    await headingLocator.waitFor({ state: 'visible', timeout: 5000 });
    return headingLocator;
  }

  async expectInstructions() {
    const instructionsLocator = this.page.locator(this.selectors.instructions);
    await instructionsLocator.waitFor({ state: 'visible', timeout: 5000 });
    return instructionsLocator;
  }
}
