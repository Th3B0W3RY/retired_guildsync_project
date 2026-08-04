/**
 * Guild Creation Page Object Model
 * Encapsulates all interactions with the guild creation form
 */

export class GuildCreationPage {
  constructor(page) {
    this.page = page;
  }

  // Selectors
  selectors = {
    nameInput: 'input[name="guild[name]"], input[type="text"][placeholder*="name" i]',
    descriptionTextarea: 'textarea[name="guild[description]"], textarea[placeholder*="description" i]',
    gameCheckbox: 'input[name="guild[game_ids][]"]',
    primaryGameRadio: 'input[name="guild[primary_game_id]"]',
    gameSearchInput: 'input[id="game-search-input"]',
    submitButton: 'input[type="submit"][value="Create Guild"]',
    errorBox: '[role="alert"], div[class*="red-950"], div.bg-red-900\\/50',
    gameSelectionError: 'div[id="game-selection-error"]'
  };

  // Navigation
  async goto() {
    await this.page.goto('/guilds/new');
    await this.page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  }

  // Actions
  async fillName(name) {
    await this.page.fill(this.selectors.nameInput, name);
  }

  async fillDescription(description) {
    const descriptionField = this.page.locator(this.selectors.descriptionTextarea);
    const hasDescription = await descriptionField.isVisible({ timeout: 2000 }).catch(() => false);
    if (hasDescription) {
      await descriptionField.fill(description);
    }
  }

  /**
   * Select a game using the CURRENT logic (may cause kickback/redirect issues)
   * This method is kept for testing the problematic flow
   */
  async selectGame(gameIdentifier = null) {
    // Select a game checkbox - use the same logic as the helper function
    const gameCheckboxes = this.page.locator(this.selectors.gameCheckbox);
    const count = await gameCheckboxes.count();
    
    if (count === 0) {
      // Try searching for a game if search input exists
      const searchInput = this.page.locator(this.selectors.gameSearchInput);
      const searchExists = await searchInput.isVisible({ timeout: 2000 }).catch(() => false);
      if (searchExists) {
        // Type "Test" to search for games (this is a valid game name)
        await searchInput.fill('Test');
        await this.page.waitForTimeout(500);
        // Try to click a select button in search results
        const selectButton = this.page.locator('button:has-text("Select")').first();
        const buttonExists = await selectButton.isVisible({ timeout: 2000 }).catch(() => false);
        if (buttonExists) {
          await selectButton.click();
          await this.page.waitForTimeout(500);
          // Get the selected game ID and set as primary
          const selectedCheckbox = this.page.locator(`${this.selectors.gameCheckbox}:checked`).first();
          const gameId = await selectedCheckbox.getAttribute('value');
          if (gameId) {
            await this.setPrimaryGame(gameId);
          }
          return;
        }
      }
      throw new Error('No game checkboxes found on the page');
    }

    // If gameIdentifier is provided, try to find matching game
    if (gameIdentifier) {
      // Try to find by value (game ID)
      const gameCheckbox = this.page.locator(`${this.selectors.gameCheckbox}[value="${gameIdentifier}"]`).first();
      const exists = await gameCheckbox.isVisible({ timeout: 2000 }).catch(() => false);
      if (exists) {
        await gameCheckbox.check();
        // Auto-select as primary if no primary is selected
        await this.setPrimaryGame(gameIdentifier);
        return;
      }
    }

    // Otherwise, select the first available game
    const firstCheckbox = gameCheckboxes.first();
    await firstCheckbox.check();
    
    // Get the game ID and set it as primary
    const gameId = await firstCheckbox.getAttribute('value');
    if (gameId) {
      await this.setPrimaryGame(gameId);
    }
  }

  /**
   * Select a game using SAFER logic that avoids kickback/redirect issues
   * This method ensures both checkbox and primary radio are properly set with proper waits
   */
  async selectGameSafely(gameIdentifier = null) {
    // Wait for game checkboxes to be available
    await this.page.waitForSelector(this.selectors.gameCheckbox, { timeout: 5000 }).catch(() => {});
    
    const gameCheckboxes = this.page.locator(this.selectors.gameCheckbox);
    const count = await gameCheckboxes.count();
    
    if (count === 0) {
      // Try searching for a game if search input exists
      const searchInput = this.page.locator(this.selectors.gameSearchInput);
      const searchExists = await searchInput.isVisible({ timeout: 2000 }).catch(() => false);
      if (searchExists) {
        // Type "Test" to search for games (this is a valid game name)
        await searchInput.fill('Test');
        await this.page.waitForTimeout(800); // Wait longer for search results
        // Try to click a select button in search results
        const selectButton = this.page.locator('button:has-text("Select")').first();
        const buttonExists = await selectButton.isVisible({ timeout: 3000 }).catch(() => false);
        if (buttonExists) {
          await selectButton.click();
          // Wait for the checkbox to appear and be checked
          await this.page.waitForTimeout(1000);
          // Verify checkbox is checked
          const selectedCheckbox = this.page.locator(`${this.selectors.gameCheckbox}:checked`).first();
          await selectedCheckbox.waitFor({ state: 'visible', timeout: 3000 });
          const gameId = await selectedCheckbox.getAttribute('value');
          if (gameId) {
            // Wait a bit more before setting primary
            await this.page.waitForTimeout(500);
            await this.setPrimaryGame(gameId);
          }
          return;
        }
      }
      throw new Error('No game checkboxes found on the page');
    }

    // If gameIdentifier is provided, try to find matching game
    if (gameIdentifier) {
      const gameCheckbox = this.page.locator(`${this.selectors.gameCheckbox}[value="${gameIdentifier}"]`).first();
      const exists = await gameCheckbox.isVisible({ timeout: 2000 }).catch(() => false);
      if (exists) {
        await gameCheckbox.check();
        // Wait for checkbox to be checked
        await this.page.waitForTimeout(500);
        await this.setPrimaryGame(gameIdentifier);
        return;
      }
    }

    // Otherwise, select the first available game
    const firstCheckbox = gameCheckboxes.first();
    await firstCheckbox.check();
    
    // Wait for checkbox to be checked before proceeding
    await this.page.waitForTimeout(500);
    
    // Verify checkbox is actually checked
    const isChecked = await firstCheckbox.isChecked();
    if (!isChecked) {
      // Try checking again
      await firstCheckbox.check();
      await this.page.waitForTimeout(500);
    }
    
    // Get the game ID and set it as primary
    const gameId = await firstCheckbox.getAttribute('value');
    if (gameId) {
      await this.setPrimaryGame(gameId);
    }
  }

  /**
   * Set primary game with proper waits and verification
   */
  async setPrimaryGame(gameId) {
    const primaryRadio = this.page.locator(`${this.selectors.primaryGameRadio}[value="${gameId}"]`).first();
    const exists = await primaryRadio.isVisible({ timeout: 3000 }).catch(() => false);
    if (exists) {
      // Wait a bit before clicking
      await this.page.waitForTimeout(300);
      await primaryRadio.click();
      // Wait after clicking
      await this.page.waitForTimeout(500);
      // Verify it's actually checked
      const isChecked = await primaryRadio.isChecked();
      if (!isChecked) {
        // Try clicking again
        await primaryRadio.click();
        await this.page.waitForTimeout(300);
      }
    }
  }

  async submit() {
    await this.page.waitForTimeout(1000);
    
    // Wait for submit button to be visible
    // Rails f.submit 'Create Guild' generates: <input type="submit" value="Create Guild">
    const submitButton = this.page.locator('input[type="submit"][value="Create Guild"]').first();
    await submitButton.waitFor({ state: 'visible', timeout: 5000 });
    
    // Submit and wait for response
    const [response] = await Promise.all([
      this.page.waitForResponse(resp => 
        resp.url().includes('/guilds') && (resp.request().method() === 'POST' || resp.status() === 302 || resp.status() === 422)
      ).catch(() => null),
      submitButton.click()
    ]);
    
    // Wait for form submission - but handle navigation gracefully
    try {
      await this.page.waitForLoadState('networkidle', { timeout: 5000 });
      // Only wait for timeout if we're still on the same page (not navigated)
      const currentUrl = this.page.url();
      if (currentUrl.includes('/guilds/new')) {
        await this.page.waitForTimeout(1000);
      }
    } catch (error) {
      // Page might have navigated or closed - that's okay
    }
    
    return response;
  }

  async submitAndWaitForSuccess(expectedGuildName = null) {
    const response = await this.submit();
    
    // Check if redirected to login (session lost)
    let currentUrl = this.page.url();
    
    if (currentUrl.includes('/login') || currentUrl.includes('/sign_in')) {
      throw new Error(
        `Session lost during form submission. Redirected to login.\n` +
        `Response status: ${response?.status() || 'unknown'}\n` +
        `Current URL: ${currentUrl}`
      );
    }
    
    // Wait for redirect to guilds page
    await this.page.waitForURL(/\/guilds\//, { timeout: 10000 });
    
    // Verify guild name appears if provided
    if (expectedGuildName) {
      await this.page.waitForSelector(`text=${expectedGuildName}`, { timeout: 5000 });
    }
  }

  async submitAndWaitForError() {
    const response = await this.submit();
    
    // Wait a moment for any navigation or error display
    try {
      await this.page.waitForLoadState('networkidle', { timeout: 3000 }).catch(() => {});
    } catch (error) {
      // Page might have navigated - check URL
    }
    
    // Check if redirected to login (session lost)
    const currentUrl = this.page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/sign_in')) {
      throw new Error(
        `Session lost during form submission. Redirected to login.\n` +
        `Response status: ${response?.status() || 'unknown'}\n` +
        `Current URL: ${currentUrl}`
      );
    }
    
    // If we navigated away from the form, we didn't get an error
    // This might mean the form submitted successfully
    if (!currentUrl.includes('/guilds/new')) {
      // Form submitted successfully - no error to show
      // Return null to indicate no error box (test should handle this)
      return null;
    }
    
    // Should still be on the form page with error displayed
    const errorBox = this.page.locator(this.selectors.errorBox).first();
    const visible = await errorBox.isVisible({ timeout: 5000 }).catch(() => false);

    return visible ? errorBox : null;
  }

  // Assertions
  async expectErrorBox() {
    const errorBox = this.page.locator(this.selectors.errorBox).first();
    await errorBox.waitFor({ state: 'visible', timeout: 5000 });
    return errorBox;
  }

  async expectErrorMessage(pattern) {
    const errorBox = await this.expectErrorBox();
    const errorMessage = errorBox.locator(`text=/${pattern}/i`);
    await errorMessage.waitFor({ state: 'visible', timeout: 2000 });
    return errorMessage;
  }

  async expectGameSelectionError() {
    const errorDiv = this.page.locator(this.selectors.gameSelectionError);
    await errorDiv.waitFor({ state: 'visible', timeout: 2000 });
    return errorDiv;
  }
}
