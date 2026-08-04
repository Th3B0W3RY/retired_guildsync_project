/**
 * Discord Connection Helpers
 * Provides utility functions for Discord OAuth and bot connection in tests
 */

/**
 * Get Discord credentials from environment variable
 * Format: USERNAME:PASSWORD
 * 
 * @returns {Object} { username: string, password: string } or null if not set
 */
export function getDiscordCredentials() {
  const credentials = process.env.DISCORD_CREDENTIALS;
  
  if (!credentials) {
    return null;
  }
  
  const [username, password] = credentials.split(':');
  
  if (!username || !password) {
    throw new Error(
      'DISCORD_CREDENTIALS environment variable must be in format USERNAME:PASSWORD'
    );
  }
  
  return { username, password };
}

/**
 * Check if Discord credentials are available
 * 
 * @returns {boolean}
 */
export function hasDiscordCredentials() {
  return !!process.env.DISCORD_CREDENTIALS;
}

/**
 * Connect Discord bot to a guild via OAuth flow
 * This handles the full Discord OAuth authorization flow
 * 
 * @param {Page} page - Playwright page object
 * @param {number} guildId - Guild ID to connect bot to
 * @returns {Promise<boolean>} True if connection successful, false otherwise
 */
export async function connectDiscordBotToGuild(page, guildId) {
  if (!hasDiscordCredentials()) {
    console.warn('[Discord Helper] DISCORD_CREDENTIALS not set. Skipping Discord connection.');
    return false;
  }
  
  const { username, password } = getDiscordCredentials();
  
  try {
    // Navigate to Discord connection page (usually /guilds/:id/discord/connect or similar)
    // The exact URL may vary - check your routes
    await page.goto(`/guilds/${guildId}/discord/connect`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);
    
    // Look for "Connect Bot" or "Authorize" button
    const connectButton = page.locator(
      'button:has-text("Connect Bot"), ' +
      'a:has-text("Connect Bot"), ' +
      'button:has-text("Connect Bot To Guild Discord"), ' +
      'button:has-text("Authorize"), ' +
      'a:has-text("Authorize")'
    ).first();
    
    const buttonVisible = await connectButton.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (!buttonVisible) {
      // Check if already connected
      const alreadyConnected = await page.locator('text=/connected|authorized/i').isVisible({ timeout: 2000 }).catch(() => false);
      if (alreadyConnected) {
        console.log('[Discord Helper] Bot already connected to guild');
        return true;
      }
      
      console.warn('[Discord Helper] Connect button not found. Bot may already be connected or page structure is different.');
      return false;
    }
    
    // Click connect button - this should redirect to Discord OAuth
    console.log('[Discord Helper] Clicking Discord connect button...');
    await connectButton.click();
    
    // Wait for Discord OAuth page to load
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(2000);
    
    // Check if we're on Discord OAuth page (discord.com/oauth2/authorize)
    const currentUrl = page.url();
    const isDiscordOAuth = currentUrl.includes('discord.com/oauth2/authorize') || 
                           currentUrl.includes('discord.com/api/oauth2/authorize');
    
    if (!isDiscordOAuth) {
      // May have redirected back already (auto-approval or already authorized)
      const backOnGuildPage = currentUrl.includes(`/guilds/${guildId}`);
      if (backOnGuildPage) {
        console.log('[Discord Helper] Already authorized or auto-approved');
        return true;
      }
      
      console.warn(`[Discord Helper] Unexpected redirect after clicking connect. URL: ${currentUrl}`);
      return false;
    }
    
    // Handle Discord login if required
    // Check if login form is visible
    const loginForm = page.locator('input[name="email"], input[type="email"]');
    const needsLogin = await loginForm.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (needsLogin) {
      console.log('[Discord Helper] Logging into Discord...');
      
      // Fill Discord login form
      await loginForm.fill(username);
      
      const passwordInput = page.locator('input[name="password"], input[type="password"]');
      await passwordInput.fill(password);
      
      // Submit login form
      const loginButton = page.locator('button[type="submit"]:has-text("Log In"), button:has-text("Login")').first();
      await loginButton.click();
      
      // Wait for login to complete
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(2000);
      
      // Check for 2FA/MFA if required
      const mfaInput = page.locator('input[name="code"], input[type="text"][placeholder*="code" i]');
      const needsMFA = await mfaInput.isVisible({ timeout: 3000 }).catch(() => false);
      
      if (needsMFA) {
        console.warn('[Discord Helper] Discord account requires 2FA. Cannot automate connection.');
        return false;
      }
    }
    
    // Authorize the application
    // Look for "Authorize" button on Discord OAuth page
    const authorizeButton = page.locator(
      'button:has-text("Authorize"), ' +
      'button[type="submit"]:has-text("Authorize"), ' +
      'button:has-text("Allow")'
    ).first();
    
    const authorizeVisible = await authorizeButton.isVisible({ timeout: 5000 }).catch(() => false);
    
    if (authorizeVisible) {
      console.log('[Discord Helper] Authorizing application...');
      await authorizeButton.click();
      
      // Wait for redirect back to application
      await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(3000);
    } else {
      // May have auto-authorized or already authorized
      console.log('[Discord Helper] Authorization may have been auto-completed');
    }
    
    // Verify we're back on the guild page and bot is connected
    const finalUrl = page.url();
    const backOnGuildPage = finalUrl.includes(`/guilds/${guildId}`);
    
    if (!backOnGuildPage) {
      console.warn(`[Discord Helper] Did not redirect back to guild page. Current URL: ${finalUrl}`);
      return false;
    }
    
    // Check if bot connection warning is gone
    const warning = page.locator('text=Bot Not Connected');
    const warningVisible = await warning.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (warningVisible) {
      console.warn('[Discord Helper] Bot connection warning still visible after OAuth flow');
      return false;
    }
    
    console.log('[Discord Helper] Discord bot successfully connected to guild');
    return true;
    
  } catch (error) {
    console.error(`[Discord Helper] Error connecting Discord bot: ${error.message}`);
    return false;
  }
}

/**
 * Check if Discord bot is connected to a guild
 * 
 * @param {Page} page - Playwright page object
 * @param {number} guildId - Guild ID to check
 * @returns {Promise<boolean>} True if connected, false otherwise
 */
export async function isDiscordBotConnected(page, guildId) {
  try {
    // Navigate to a page that shows Discord connection status
    // This could be the guild settings page, event creation page, or members invite page
    await page.goto(`/guilds/${guildId}/events/schedule`);
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);
    
    // Check for "Bot Not Connected" warning
    const warning = page.locator('text=Bot Not Connected, div:has-text("Bot Not Connected")');
    const warningVisible = await warning.isVisible({ timeout: 3000 }).catch(() => false);
    
    return !warningVisible;
  } catch (error) {
    console.error(`[Discord Helper] Error checking Discord connection: ${error.message}`);
    return false;
  }
}

/**
 * Ensure Discord bot is connected to a guild, attempting connection if needed
 * 
 * @param {Page} page - Playwright page object
 * @param {number} guildId - Guild ID to ensure connection for
 * @returns {Promise<boolean>} True if connected (or connection successful), false otherwise
 */
export async function ensureDiscordBotConnected(page, guildId) {
  // First check if already connected
  const isConnected = await isDiscordBotConnected(page, guildId);
  
  if (isConnected) {
    return true;
  }
  
  // Attempt to connect
  if (!hasDiscordCredentials()) {
    console.warn('[Discord Helper] DISCORD_CREDENTIALS not set. Cannot connect Discord bot.');
    return false;
  }
  
  return await connectDiscordBotToGuild(page, guildId);
}
