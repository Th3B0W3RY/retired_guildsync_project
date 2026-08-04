/**
 * Test Helpers for GuildSync Integration Tests
 * Provides utility functions for common test operations
 */

import { expect } from '@playwright/test';
import { getBaseURL, getAPIBaseURL } from '../../config/test-config.js';

// Re-export Discord helpers for convenience
export { 
  getDiscordCredentials, 
  hasDiscordCredentials, 
  connectDiscordBotToGuild, 
  isDiscordBotConnected,
  ensureDiscordBotConnected 
} from './discord-helpers.js';

/**
 * Generate a unique email address for testing
 */
export function generateTestEmail(prefix = 'test') {
  const timestamp = Date.now();
  const random = Math.floor(Math.random() * 10000);
  return `${prefix}_${timestamp}_${random}@test.example.com`;
}

/**
 * Generate a unique username for testing
 * Username must be <= 30 characters (backend requirement)
 * Format: ${prefix}_${timestamp}_${random}
 * Timestamp is ~13 digits, random is up to 4 digits, plus 2 underscores = ~19 chars
 * So prefix can be up to 11 characters to stay under 30
 */
export function generateTestUsername(prefix = 'test') {
  const timestamp = Date.now();
  const random = Math.floor(Math.random() * 10000);
  
  // Calculate max prefix length: 30 total - timestamp (13) - random (4) - 2 underscores = 11
  const maxPrefixLength = 30 - 13 - 4 - 2; // 11 characters
  const truncatedPrefix = prefix.length > maxPrefixLength 
    ? prefix.substring(0, maxPrefixLength) 
    : prefix;
  
  return `${truncatedPrefix}_${timestamp}_${random}`;
}

/**
 * Create a new test user via API and return authentication token
 * This is useful for tests that need a fresh user without existing data (e.g., guild limits)
 * 
 * @param {Object} request - Playwright request object (from test context)
 * @param {Object} options - Optional configuration
 * @param {string} options.emailPrefix - Prefix for generated email (default: 'test')
 * @param {string} options.emailAffix - Affix to append to email prefix (optional)
 * @param {string} options.usernamePrefix - Prefix for generated username (default: 'test')
 * @param {string} options.usernameAffix - Affix to append to username prefix (optional)
 * @param {string} options.password - Password to use (default: 'TestPassword123!')
 * @param {boolean} options.skip_mfa_verification - When true, API test env auto-skips MFA (Rails test only). Default: true
 * @param {string} options.authMethod - 'mfa' (default) or 'discord'. MFA users get OTP auto-verified in test; use 'discord' to match seeded users that bypass MFA in browser tests.
 * @returns {Promise<Object>} Object with { token, email, username, password, user }
 */
export async function createTestUserAndGetToken(request, options = {}) {
  const API_BASE_URL = getAPIBaseURL();
  const {
    emailPrefix = 'test',
    emailAffix = '',
    usernamePrefix = 'test',
    usernameAffix = '',
    password = 'TestPassword123!',
    skip_mfa_verification = true, // Default to skipping MFA for most tests
    authMethod = 'mfa',
  } = options;
  
  // Construct full prefix with affix if provided
  const fullEmailPrefix = emailAffix ? `${emailPrefix}_${emailAffix}` : emailPrefix;
  const fullUsernamePrefix = usernameAffix ? `${usernamePrefix}_${usernameAffix}` : usernamePrefix;

  const testEmail = generateTestEmail(fullEmailPrefix);
  const testUsername = generateTestUsername(fullUsernamePrefix);

  // Sign up new user
  const signUpData = {
    user: {
      email: testEmail,
      username: testUsername,
      password: password,
      password_confirmation: password,
      skip_mfa_verification: skip_mfa_verification, // Send to backend
      auth_method: authMethod // discord bypasses MFA, mfa requires MFA
    }
  };
  
  const signUpResponse = await request.post(`${API_BASE_URL}/auth/sign_up`, {
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    data: signUpData
  });

  if (signUpResponse.status() !== 201) {
    const text = await signUpResponse.text().catch(() => '');
    throw new Error(
      `Failed to create test user. Status: ${signUpResponse.status()}. ` +
      `Response: ${text.substring(0, 200)}`
    );
  }

  const signUpBody = await signUpResponse.json().catch(() => ({}));
  const user = signUpBody.user || { email: testEmail, username: testUsername };

  // Sign in the new user to get a token
  const signInResponse = await request.post(`${API_BASE_URL}/auth/sign_in`, {
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    data: {
      user: {
        email: testEmail,
        password: password
      }
    }
  });

  if (signInResponse.status() !== 200) {
    const text = await signInResponse.text().catch(() => '');
    throw new Error(
      `Failed to sign in test user. Status: ${signInResponse.status()}. ` +
      `Response: ${text.substring(0, 200)}`
    );
  }

  const signInBody = await signInResponse.json().catch(() => ({}));
  
  if (!signInBody.token) {
    throw new Error(
      `No token in sign-in response. Body: ${JSON.stringify(signInBody)}`
    );
  }

  return {
    token: signInBody.token,
    email: testEmail,
    username: testUsername,
    password: password,
    user: user
  };
}

/**
 * Create a confirmed MFA user that has not completed MFA setup, then sign in
 * through the browser so tests can exercise the real /mfa/setup UI.
 */
export async function createMFASetupUserAndLogin(page, request, options = {}) {
  const API_BASE_URL = getAPIBaseURL();
  const {
    emailPrefix = 'mfa_setup',
    usernamePrefix = 'mfa_setup',
    password = 'TestPassword123!'
  } = options;

  const email = generateTestEmail(emailPrefix);
  const username = generateTestUsername(usernamePrefix);

  const signUpResponse = await request.post(`${API_BASE_URL}/auth/sign_up`, {
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    data: {
      user: {
        email,
        username,
        password,
        password_confirmation: password,
        test_confirm_email: true,
        test_skip_mfa_auto_setup: true
      }
    }
  });

  if (signUpResponse.status() !== 201) {
    const text = await signUpResponse.text().catch(() => '');
    throw new Error(
      `Failed to create MFA setup test user. Status: ${signUpResponse.status()}. ` +
      `Response: ${text.substring(0, 200)}`
    );
  }

  await loginUser(page, { email, password, skipMFA: true });
  await expectNavigation(page, '/mfa/setup', 10000);

  return { email, username, password };
}

/**
 * Parse Blueprint render output that may be a JSON string or already parsed
 * GuildBlueprint.render() sometimes returns a JSON string instead of an object/array
 * 
 * @param {string|Object|Array} value - The value that might be a JSON string
 * @returns {Object|Array} - The parsed object or array, or the original value if already parsed
 */
export function parseBlueprintResponse(value) {
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (e) {
      // If parsing fails, return the original string
      return value;
    }
  }
  return value;
}

/**
 * Wait for navigation and verify we're on the expected page
 * Handles URLs with query parameters by using regex pattern
 */
export async function expectNavigation(page, expectedPath, timeout = 5000) {
  // Check for rate limit error first
  const hasError = await hasRateLimitError(page);
  if (hasError) {
    throw new Error('Rate limit error detected. Please restart the Rails server.');
  }
  
  // Use regex pattern to match path with optional query parameters
  // Escape special regex characters in the path, but allow / to remain
  // This handles URLs like /mfa/verify?return_to=/dashboard
  const escapedPath = expectedPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // Match the path, optionally followed by query string or hash
  // The pattern matches: path (optionally followed by ?query or #hash)
  const urlPattern = new RegExp(`${escapedPath}(?:[?#].*)?$`);
  
  await page.waitForURL(urlPattern, { timeout });
  expect(page.url()).toMatch(urlPattern);
}

/**
 * Fill login form with rate limit checking
 */
export async function fillLoginForm(page, { email, password }) {
  // Check for rate limit error before filling
  const hasError = await hasRateLimitError(page);
  if (hasError) {
    throw new Error('Rate limit error on page. Please restart the Rails server.');
  }
  
  // Wait for form fields to be visible
  await waitForElementWithRateLimitCheck(page, 'input[name="user[email]"]', { timeout: 10000 });
  
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
}

/**
 * Click submit button in a form (works with both input and button submit elements)
 */
export async function clickSubmitButton(page) {
  // Rails f.submit generates <input type="submit">, not <button type="submit">
  // Use a selector that works with both
  await page.click('input[type="submit"], button[type="submit"]');
}

/**
 * Complete MFA setup flow
 * Note: This requires the OTP code to be provided by the test
 * @deprecated Use MfaVerificationPage or MfaSetupPage page objects instead
 */
export async function completeMFASetup(page, otpCode) {
  // Wait for MFA input field to be visible
  // Updated to match ERB form: input[name="code"]
  const mfaInput = page.locator('input[name="code"], input[name="otp_code"], input[name="mfa_code"], input[type="text"][placeholder*="code" i], input[type="text"][placeholder*="OTP" i]');
  await mfaInput.waitFor({ state: 'visible', timeout: 5000 });
  await mfaInput.fill(otpCode);
  
  // Find and click submit button (Rails forms use input[type="submit"]; exclude generic button[type="submit"] which matches Sign Out)
  const submitButton = page.locator('input[type="submit"], button:has-text("Verify"), button:has-text("Submit")').first();
  await submitButton.click();
  
  // Wait for navigation or response
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
}

/**
 * Complete MFA verification (for login flow)
 * Similar to setup but used during login
 */
export async function completeMFAVerification(page, otpCode) {
  return completeMFASetup(page, otpCode); // Same implementation
}

/**
 * Generate TOTP code from secret
 * Note: For production tests, install 'otplib' package: npm install otplib
 * This is a placeholder - actual implementation should use a proper TOTP library
 */
export function generateTOTPCode(secret) {
  // Placeholder - in real implementation, use a proper TOTP library like 'otplib'
  // Example with otplib:
  // import { authenticator } from 'otplib';
  // return authenticator.generate(secret);
  throw new Error('TOTP generation requires a proper library. Install otplib or provide code manually in tests.');
}

/**
 * Wait for and verify success message
 */
export async function expectSuccessMessage(page, messageText) {
  const message = page.locator(`text=${messageText}`).first();
  await expect(message).toBeVisible({ timeout: 5000 });
}

/**
 * Wait for and verify error message
 */
export async function expectErrorMessage(page, messageText) {
  const message = page.locator(`text=${messageText}`).first();
  await expect(message).toBeVisible({ timeout: 5000 });
}

/**
 * Log in a discord-auth user and navigate to /dashboard to settle session[:mfa_verified].
 * Discord users bypass MFA but may briefly land on /mfa/setup after the initial redirect;
 * hitting any protected page (e.g. /dashboard) causes require_mfa_if_enabled to set the flag.
 *
 * @param {Object} page - Playwright page object
 * @param {string} email
 * @param {string} password
 */
export async function loginAndSettle(page, email, password) {
  await page.goto('/login');
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.click('input[type="submit"], button[type="submit"]');
  await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(500);
  // Force session[:mfa_verified] for discord-auth users
  await page.goto('/dashboard');
  await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(500);
}

/**
 * Create a guild via the JSON API and return its id.
 * Handles Blueprint responses that may serialise guild data as a JSON string.
 *
 * @param {Object} request - Playwright request fixture
 * @param {string} token   - Bearer token for the guild owner
 * @param {string} name    - Guild name
 * @returns {Promise<number>} guild id
 */
export async function createGuildViaAPI(request, token, name) {
  const res = await request.post(`${getAPIBaseURL()}/guilds`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json'
    },
    data: { guild: { name } }
  });
  if (![200, 201].includes(res.status())) {
    throw new Error(`Guild creation failed: ${res.status()}`);
  }
  const body = await res.json();
  const guild = parseBlueprintResponse(body.guild);
  if (!guild?.id) throw new Error('No guild id in API response');
  return guild.id;
}

/**
 * Login as a user (assumes user exists)
 * Note: Users with auth_method: "discord" bypass MFA
 */
export async function loginUser(page, { email, password, baseURL = getBaseURL(), skipMFA = false }) {
  await page.goto(`${baseURL}/login`);
  await fillLoginForm(page, { email, password });
  await page.click('input[type="submit"], button[type="submit"]');
  
  // Wait for response
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  
  // Handle MFA if required
  const currentUrl = page.url();
  const mfaRequired = currentUrl.includes('/mfa/verify') || 
                     await page.locator('text=/MFA|Two-Factor|Verify/i').isVisible({ timeout: 2000 }).catch(() => false);
  
  if (mfaRequired && !skipMFA) {
    // If MFA is required and not skipped, throw error
    // Tests should either use users with auth_method: "discord" or handle MFA separately
    throw new Error('MFA verification required. Use a user with auth_method: "discord" or handle MFA in test');
  }
  
  // Wait for successful login (redirect to dashboard, MFA setup, or home)
  // MFA setup is for new users who haven't completed MFA yet
  await page.waitForURL(/\/(dashboard|guilds|home|mfa\/setup)/, { timeout: 10000 });
}

/**
 * Login and handle MFA verification (if required)
 * Returns true if login was successful, false if MFA is required
 */
export async function loginUserWithMFA(page, { email, password, otpCode = null, baseURL = getBaseURL() }) {
  await page.goto(`${baseURL}/login`);
  await fillLoginForm(page, { email, password });
  await page.click('input[type="submit"], button[type="submit"]');
  
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  
  const currentUrl = page.url();
  const mfaRequired = currentUrl.includes('/mfa/verify');
  
  if (mfaRequired) {
    if (!otpCode) {
      return false; // MFA required but no code provided
    }
    
    // Complete MFA verification
    await completeMFASetup(page, otpCode);
    await page.waitForURL(/\/(dashboard|guilds|home)/, { timeout: 10000 });
    return true;
  }
  
  // No MFA required, login successful
  await page.waitForURL(/\/(dashboard|guilds|home|mfa\/setup)/, { timeout: 10000 });
  return true;
}

/**
 * Wait for element to be visible and clickable
 */
export async function waitAndClick(page, selector, options = {}) {
  const element = page.locator(selector);
  await element.waitFor({ state: 'visible', timeout: options.timeout || 5000 });
  await element.click();
}

/**
 * Verify subscription status
 */
export async function verifySubscriptionStatus(page, expectedStatus) {
  // This will depend on how subscription status is displayed in the UI
  // Adjust selector based on actual implementation
  const statusElement = page.locator(`text=${expectedStatus}`);
  await expect(statusElement).toBeVisible({ timeout: 5000 });
}

/**
 * Clean up test data (if needed)
 * This would typically be done via API or database cleanup
 */
export async function cleanupTestUser(email) {
  // Placeholder - implement based on your cleanup strategy
  console.log(`Cleanup test user: ${email}`);
}

/**
 * Extract CSRF token from page
 */
export async function getCSRFToken(page) {
  const token = await page.locator('meta[name="csrf-token"]').getAttribute('content');
  return token;
}

/**
 * Make authenticated API request
 */
export async function apiRequest(page, method, url, data = {}, token = null) {
  const csrfToken = token || await getCSRFToken(page);
  
  const response = await page.request.fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      ...(token && { 'Authorization': `Bearer ${token}` })
    },
    ...(data && { data })
  });
  
  return response;
}

/**
 * Handle rate limiting with retry logic
 * @param {Object} response - Playwright API response
 * @param {Function} retryFn - Function to retry the request
 * @param {number} maxRetries - Maximum number of retries
 * @returns {Promise<Object>} Response after handling rate limits
 */
export async function handleRateLimit(response, retryFn, maxRetries = 3) {
  if (response.status() === 429) {
    const retryAfter = response.headers()['retry-after'];
    const waitTime = retryAfter ? parseInt(retryAfter) * 1000 : 2000;
    
    if (maxRetries > 0) {
      console.log(`Rate limited (429). Waiting ${waitTime}ms before retry...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
      return retryFn();
    } else {
      throw new Error('Rate limit exceeded. Please restart the Rails server to clear rate limit cache, or wait before running tests again.');
    }
  }
  return response;
}

/**
 * Check if page shows a rate limit error
 * @param {Object} page - Playwright page object
 * @returns {Promise<boolean>} True if rate limit error is visible
 */
export async function hasRateLimitError(page) {
  try {
    const rateLimitText = page.locator('text=/rate limit|429|exceeded/i');
    const rateLimitJson = page.locator('text=/Rate limit exceeded/i');
    const hasText = await rateLimitText.isVisible({ timeout: 1000 }).catch(() => false);
    const hasJson = await rateLimitJson.isVisible({ timeout: 1000 }).catch(() => false);
    
    // Also check page content for JSON error
    const bodyText = await page.textContent('body').catch(() => '');
    const hasJsonInBody = bodyText.includes('Rate limit exceeded') || bodyText.includes('"error"');
    
    return hasText || hasJson || hasJsonInBody;
  } catch {
    return false;
  }
}

/**
 * Wait for page to load without rate limit error, with retry
 * @param {Object} page - Playwright page object
 * @param {Function} navigateFn - Function to navigate (e.g., () => page.goto('/path'))
 * @param {number} maxRetries - Maximum retries
 * @param {number} waitTime - Wait time between retries in ms
 */
export async function waitForPageWithoutRateLimit(page, navigateFn, maxRetries = 3, waitTime = 3000) {
  for (let i = 0; i < maxRetries; i++) {
    await navigateFn();
    
    // Wait a bit for page to load
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    
    const hasError = await hasRateLimitError(page);
    if (!hasError) {
      return; // Page loaded successfully
    }
    
    if (i < maxRetries - 1) {
      console.log(`Rate limit detected on page. Waiting ${waitTime}ms before retry (${maxRetries - i - 1} retries left)...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
  
  throw new Error('Page still showing rate limit error after retries. Please restart the Rails server.');
}

/**
 * Navigate to a page and wait for it to load without rate limit errors
 * @param {Object} page - Playwright page object
 * @param {string} url - URL to navigate to
 * @param {Object} options - Navigation options
 */
export async function gotoWithRateLimitHandling(page, url, options = {}) {
  const maxRetries = options.maxRetries || 3;
  const waitTime = options.waitTime || 3000;
  
  await waitForPageWithoutRateLimit(
    page,
    () => page.goto(url, { waitUntil: 'networkidle', timeout: 30000 }),
    maxRetries,
    waitTime
  );
}

/**
 * Wait for element to be visible, handling rate limit errors
 * @param {Object} page - Playwright page object
 * @param {string} selector - Element selector
 * @param {Object} options - Options with timeout
 */
export async function waitForElementWithRateLimitCheck(page, selector, options = {}) {
  const timeout = options.timeout || 5000;
  const maxRetries = 3;
  
  for (let i = 0; i < maxRetries; i++) {
    // Check for rate limit error first
    const hasError = await hasRateLimitError(page);
    if (hasError) {
      if (i < maxRetries - 1) {
        console.log(`Rate limit detected. Waiting 3000ms before retry...`);
        await new Promise(resolve => setTimeout(resolve, 3000));
        await page.reload({ waitUntil: 'networkidle' });
        continue;
      } else {
        throw new Error('Rate limit error on page. Please restart the Rails server.');
      }
    }
    
    // Try to find the element
    try {
      const element = page.locator(selector);
      await element.waitFor({ state: 'visible', timeout });
      return element;
    } catch (error) {
      if (i === maxRetries - 1) {
        throw error;
      }
      // Wait and retry
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

/**
 * Select a game in guild creation form
 * Handles different UI patterns: checkboxes, select dropdowns, or autocomplete inputs
 * @param {Object} page - Playwright page object
 * @param {string|number} gameIdentifier - Game name, ID, or index
 */
export async function selectGameInGuildForm(page, gameIdentifier = null) {
  // Try checkbox first (most common pattern)
  const gameCheckbox = page.locator('input[type="checkbox"][name*="game"], input[type="checkbox"][name*="game_ids"]').first();
  const hasCheckbox = await gameCheckbox.isVisible({ timeout: 2000 }).catch(() => false);
  
  if (hasCheckbox) {
    await gameCheckbox.check();
    return;
  }
  
  // Try select dropdown
  const gameSelect = page.locator('select[name*="game"], select[name*="primary_game"], select[name*="game_ids"]').first();
  const hasSelect = await gameSelect.isVisible({ timeout: 2000 }).catch(() => false);
  
  if (hasSelect) {
    if (typeof gameIdentifier === 'number') {
      await gameSelect.selectOption({ index: gameIdentifier });
    } else if (gameIdentifier) {
      await gameSelect.selectOption({ label: gameIdentifier });
    } else {
      await gameSelect.selectOption({ index: 1 }); // Select first option
    }
    return;
  }
  
  // Try autocomplete/input field
  const gameInput = page.locator('input[name*="game"], input[type="text"][placeholder*="game" i], input[autocomplete*="game" i]').first();
  const hasInput = await gameInput.isVisible({ timeout: 2000 }).catch(() => false);
  
  if (hasInput) {
    const gameName = gameIdentifier || 'Test Game';
    await gameInput.fill(gameName);
    await page.waitForTimeout(500); // Wait for autocomplete
    await page.keyboard.press('Enter');
    return;
  }
  
  // If no game selection found, log a warning but don't fail
  console.warn('No game selection field found. Guild creation may fail if games are required.');
}

/**
 * Set primary game in guild creation form
 * @param {Object} page - Playwright page object
 * @param {string|number} gameIdentifier - Game name, ID, or index
 */
export async function setPrimaryGameInGuildForm(page, gameIdentifier = null) {
  // Try to find primary game selector - could be select, input, or radio button
  const primaryGameSelect = page.locator('select[name*="primary_game"], input[name*="primary_game"], input[type="radio"][name*="primary_game"]').first();
  const hasPrimaryGame = await primaryGameSelect.isVisible({ timeout: 2000 }).catch(() => false);
  
  if (hasPrimaryGame) {
    const inputType = await primaryGameSelect.getAttribute('type').catch(() => null);
    const tagName = await primaryGameSelect.evaluate(el => el.tagName);
    
    if (tagName === 'SELECT') {
      // Select dropdown
      if (typeof gameIdentifier === 'number') {
        await primaryGameSelect.selectOption({ index: gameIdentifier });
      } else if (gameIdentifier) {
        await primaryGameSelect.selectOption({ label: gameIdentifier });
      } else {
        await primaryGameSelect.selectOption({ index: 1 });
      }
    } else if (inputType === 'radio') {
      // Radio button - click it, don't fill it
      await primaryGameSelect.click();
    } else {
      // Input field (text/autocomplete)
      const gameName = gameIdentifier || 'Test Game';
      await primaryGameSelect.fill(gameName);
      await page.waitForTimeout(500);
      await page.keyboard.press('Enter');
    }
  }
}
