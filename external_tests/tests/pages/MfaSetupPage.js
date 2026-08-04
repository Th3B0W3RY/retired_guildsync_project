/**
 * MFA Setup Page Object Model
 * Encapsulates all interactions with the MFA setup page
 */

export class MfaSetupPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    qrCode: 'svg, img[alt*="QR"], canvas',
    otpInput: 'input[name="code"], input[name="otp_code"], input[name="mfa_code"], input[type="text"][placeholder*="code" i], input[type="text"][placeholder*="OTP" i]',
    submitButton: 'button[type="submit"], button:has-text("Verify"), button:has-text("Submit")',
    manualEntry: 'text=/manual|secret|key|code/i',
    instructions: 'text=/scan|QR|code|authenticator/i',
    setupPrompt: 'text=/MFA|Two-Factor|Setup/i',
    errorMessage: 'text=/invalid|expired|incorrect/i'
  };

  // Navigation
  async goto() {
    await this.page.goto('/mfa/setup');
  }

  // Actions
  async fillOtpCode(code) {
    const otpInput = this.page.locator(this.selectors.otpInput);
    await otpInput.waitFor({ state: 'visible', timeout: 5000 });
    await otpInput.fill(code);
  }

  async submit() {
    const submitButton = this.page.locator(this.selectors.submitButton);
    await submitButton.click();
  }

  async completeSetup(code) {
    await this.fillOtpCode(code);
    await this.submit();
  }

  // Assertions
  async expectQrCode() {
    const qrLocator = this.page.locator(this.selectors.qrCode).first();
    await qrLocator.waitFor({ state: 'visible', timeout: 5000 });
    return qrLocator;
  }

  async expectInstructions() {
    const instructionsLocator = this.page.locator(this.selectors.instructions);
    await instructionsLocator.waitFor({ state: 'visible', timeout: 5000 });
    return instructionsLocator;
  }

  async expectSetupPrompt() {
    // Use the h1 heading which is most specific: "Enable Multi-Factor Authentication"
    const headingLocator = this.page.locator('h1:has-text("Enable Multi-Factor Authentication"), h1:has-text("MFA"), h1:has-text("Two-Factor")').first();
    const headingExists = await headingLocator.isVisible({ timeout: 2000 }).catch(() => false);
    
    if (headingExists) {
      await headingLocator.waitFor({ state: 'visible', timeout: 5000 });
      return headingLocator;
    }
    
    // Fallback: Look for setup-related text that's NOT in buttons or labels
    const promptLocator = this.page.locator('text=/MFA|Two-Factor|Setup/i')
      .filter({ 
        hasNot: this.page.locator('button, input[type="submit"], label') 
      })
      .first();
    
    await promptLocator.waitFor({ state: 'visible', timeout: 5000 });
    return promptLocator;
  }

  async expectErrorMessage() {
    // Error toasts are created dynamically by toast_controller.js with role="alert".
    // The primary selector targets the toast element; the fallback catches the text inside it.
    const alertLocator = this.page.locator('[role="alert"]').first();
    const alertExists = await alertLocator.isVisible({ timeout: 4000 }).catch(() => false);

    if (alertExists) {
      await alertLocator.waitFor({ state: 'visible', timeout: 5000 });
      return alertLocator;
    }

    // Fallback: look for error text in any non-structural element
    const errorText = this.page.locator('text=/invalid|incorrect|wrong|error|expired/i')
      .filter({
        hasNot: this.page.locator('h1, h2, label, button, input[type="submit"], p.text-theme-secondary, p.text-sm')
      })
      .first();

    await errorText.waitFor({ state: 'visible', timeout: 5000 });
    return errorText;
  }
}
