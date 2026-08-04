import { test, expect } from '@playwright/test';
import { generateTestEmail, generateTestUsername } from '../../helpers/test-helpers';
import { getAPIBaseURL } from '../../../config/test-config.js';

const API_BASE_URL = getAPIBaseURL();

// Helper to handle rate limiting with retry
async function handleRateLimit(response, retryFn, maxRetries = 3) {
  if (response.status() === 429) {
    const retryAfter = response.headers()['retry-after'];
    const waitTime = retryAfter ? parseInt(retryAfter) * 1000 : 3000;
    
    if (maxRetries > 0) {
      console.log(`Rate limited (429). Waiting ${waitTime}ms before retry (${maxRetries} retries left)...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
      const newResponse = await retryFn();
      return handleRateLimit(newResponse, retryFn, maxRetries - 1);
    } else {
      const text = await response.text().catch(() => '');
      throw new Error(`Rate limit exceeded after retries. Response: ${text.substring(0, 200)}`);
    }
  }
  return response;
}

// Helper to safely parse JSON response
async function safeJsonParse(response) {
  const contentType = response.headers()['content-type'] || '';
  if (!contentType.includes('application/json')) {
    const text = await response.text();
    throw new Error(`Expected JSON but got ${contentType}. Response: ${text.substring(0, 200)}`);
  }
  try {
    return await response.json();
  } catch (error) {
    const text = await response.text();
    throw new Error(`Failed to parse JSON. Status: ${response.status()}. Response: ${text.substring(0, 200)}`);
  }
}

test.describe('API Authentication', () => {
  // Note: Tests will handle missing users gracefully with clear error messages
  // No need to skip all tests in beforeAll - individual tests handle their own prerequisites

  test('should successfully sign up via API', async ({ request }) => {
    const email = generateTestEmail('api');
    const username = generateTestUsername('api');
    const password = 'TestPassword123!';

    const makeRequest = async () => {
      return await request.post(`${API_BASE_URL}/auth/sign_up`, {
        data: {
          user: {
            email,
            username,
            password,
            password_confirmation: password
          }
        }
      });
    };

    let response = await makeRequest();
    
    // Handle rate limiting
    if (response.status() === 429) {
      response = await handleRateLimit(response, makeRequest);
    }

    expect(response.status()).toBe(201);
    
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('user');
    expect(body.user).toHaveProperty('email', email);
    expect(body.user).toHaveProperty('username', username);
  });

  test('should successfully sign in via API', async ({ request }) => {
    // This test assumes a test user exists
    // Users with auth_method: "discord" bypass MFA and return token immediately
    // Other users may require MFA verification
    const email = 'test_data@example.com';
    const password = 'password123';

    const makeRequest = async () => {
      return await request.post(`${API_BASE_URL}/auth/sign_in`, {
        data: {
          user: {
            email,
            password
          }
        }
      });
    };

    let response = await makeRequest();
    
    // Handle rate limiting
    if (response.status() === 429) {
      response = await handleRateLimit(response, makeRequest);
    }

    // API may return 200 with token (for Discord auth users) or 200 with mfa_required flag
    const status = response.status();
    
    if (status === 401) {
      // Test user doesn't exist - provide helpful error message
      const errorBody = await response.json().catch(() => ({}));
      const errorMessage = errorBody.error || errorBody.message || 'Invalid email or password';
      throw new Error(
        `Authentication failed. Test user may not be configured.\n` +
        `Status: ${status}\n` +
        `Error: ${errorMessage}\n` +
        `\nThis indicates a setup issue. Run: npm run test:verify\n` +
        `Or create test user in Rails console with email: ${email}`
      );
    }
    
    // Should succeed (200 or 201)
    expect([200, 201]).toContain(status);
    
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('user');
    
    // If MFA is required, token may not be present - that's acceptable
    if (body.mfa_required) {
      expect(body).toHaveProperty('mfa_required', true);
      // MFA required is a valid response - test passes
    } else {
      // No MFA required - should have token
      expect(body).toHaveProperty('token'); // JWT token for users without MFA requirement
      expect(typeof body.token).toBe('string');
      expect(body.token.length).toBeGreaterThan(0);
    }
  });

  test('should return error for invalid credentials', async ({ request }) => {
    const makeRequest = async () => {
      return await request.post(`${API_BASE_URL}/auth/sign_in`, {
        data: {
          user: {
            email: 'nonexistent@example.com',
            password: 'wrongpassword'
          }
        }
      });
    };

    let response = await makeRequest();
    
    // Handle rate limiting - but still expect 401 for invalid credentials
    if (response.status() === 429) {
      response = await handleRateLimit(response, makeRequest);
    }

    // Should be 401 for invalid credentials, not 200 or 429
    expect(response.status()).toBe(401);
  });

  test('should return current user info with valid token', async ({ request }) => {
    
    // First, sign in to get a token
    // Use a user with auth_method: "discord" to bypass MFA, or handle MFA if required
    const email = 'test_data@example.com';
    const password = 'password123';

    const makeLoginRequest = async () => {
      return await request.post(`${API_BASE_URL}/auth/sign_in`, {
        data: {
          user: {
            email,
            password
          }
        }
      });
    };

    let loginResponse = await makeLoginRequest();
    
    // Handle rate limiting
    if (loginResponse.status() === 429) {
      loginResponse = await handleRateLimit(loginResponse, makeLoginRequest);
    }

    if (loginResponse.status() === 401) {
      throw new Error(
        `Cannot get token - test user authentication failed.\n` +
        `Status: ${loginResponse.status()}\n` +
        `Run: npm run test:verify to set up test user`
      );
    }

    expect([200, 201]).toContain(loginResponse.status());
    const loginBody = await safeJsonParse(loginResponse);
    
    // If MFA is required, we cannot get a token without completing MFA verification
    // This test requires a user without MFA (auth_method: "discord")
    if (loginBody.mfa_required) {
      throw new Error(
        `MFA verification required - cannot get token without completing MFA verification flow.\n` +
        `Test user should have auth_method: "discord" to bypass MFA.\n` +
        `Current response: ${JSON.stringify(loginBody)}`
      );
    }
    
    const token = loginBody.token;
    if (!token) {
      throw new Error(
        `Expected token in login response but got: ${JSON.stringify(loginBody)}\n` +
        `User may require MFA verification or token field is missing`
      );
    }
    expect(token).toBeTruthy();
    expect(typeof token).toBe('string');
    expect(token.length).toBeGreaterThan(0);

    // Use token to get current user
    const makeMeRequest = async () => {
      return await request.get(`${API_BASE_URL}/auth/me`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json'
        }
      });
    };

    let meResponse = await makeMeRequest();
    
    // Handle rate limiting
    if (meResponse.status() === 429) {
      meResponse = await handleRateLimit(meResponse, makeMeRequest);
    }

    if (meResponse.status() === 500) {
      const errorText = await meResponse.text().catch(() => '');
      throw new Error(
        `Server error (500) when getting current user info.\n` +
        `This indicates a backend error. Check server logs.\n` +
        `Response: ${errorText.substring(0, 500)}`
      );
    }

    if (meResponse.status() === 401) {
      throw new Error(
        `Token authentication failed. Status: ${meResponse.status()}\n` +
        `Token may be invalid or expired. Response: ${await meResponse.text().catch(() => '')}`
      );
    }

    expect(meResponse.status()).toBe(200);
    const meBody = await safeJsonParse(meResponse);
    expect(meBody).toHaveProperty('user');
    expect(meBody.user).toHaveProperty('email', email);
  });

  test('should return error for invalid token', async ({ request }) => {
    const makeRequest = async () => {
      return await request.get(`${API_BASE_URL}/auth/me`, {
        headers: {
          'Authorization': 'Bearer invalid_token_here',
          'Accept': 'application/json'
        }
      });
    };

    let response = await makeRequest();
    
    // Handle rate limiting
    if (response.status() === 429) {
      response = await handleRateLimit(response, makeRequest);
    }

    // Should be 401 for invalid token, not 200 or 429
    if (response.status() !== 401) {
      const responseText = await response.text().catch(() => '');
      throw new Error(
        `Expected 401 for invalid token but got ${response.status()}.\n` +
        `Response: ${responseText.substring(0, 500)}\n` +
        `The /auth/me endpoint should require valid authentication.`
      );
    }
    expect(response.status()).toBe(401);
  });

  test('should successfully sign out via API', async ({ request }) => {
    
    // First, sign in to get a token
    // Use a user with auth_method: "discord" to bypass MFA, or handle MFA if required
    const email = 'test_data@example.com';
    const password = 'password123';

    const makeLoginRequest = async () => {
      return await request.post(`${API_BASE_URL}/auth/sign_in`, {
        data: {
          user: {
            email,
            password
          }
        }
      });
    };

    let loginResponse = await makeLoginRequest();
    
    // Handle rate limiting
    if (loginResponse.status() === 429) {
      loginResponse = await handleRateLimit(loginResponse, makeLoginRequest);
    }

    if (loginResponse.status() === 401) {
      throw new Error(
        `Cannot get token for sign out test - test user authentication failed.\n` +
        `Status: ${loginResponse.status()}\n` +
        `Run: npm run test:verify to set up test user`
      );
    }

    expect([200, 201]).toContain(loginResponse.status());
    const loginBody = await safeJsonParse(loginResponse);
    
    // If MFA is required, we cannot get a token without completing MFA verification
    // This test requires a user without MFA (auth_method: "discord")
    if (loginBody.mfa_required) {
      throw new Error(
        `MFA verification required - cannot get token for sign out without completing MFA verification flow.\n` +
        `Test user should have auth_method: "discord" to bypass MFA.\n` +
        `Current response: ${JSON.stringify(loginBody)}`
      );
    }
    
    const token = loginBody.token;
    if (!token) {
      throw new Error(
        `Expected token in login response but got: ${JSON.stringify(loginBody)}\n` +
        `User may require MFA verification or token field is missing`
      );
    }
    expect(token).toBeTruthy();
    expect(typeof token).toBe('string');
    expect(token.length).toBeGreaterThan(0);

    // Sign out
    const makeSignOutRequest = async () => {
      return await request.delete(`${API_BASE_URL}/auth/sign_out`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json'
        }
      });
    };

    let signOutResponse = await makeSignOutRequest();
    
    // Handle rate limiting
    if (signOutResponse.status() === 429) {
      signOutResponse = await handleRateLimit(signOutResponse, makeSignOutRequest);
    }

    // Check for server errors
    if (signOutResponse.status() === 500) {
      const errorText = await signOutResponse.text().catch(() => '');
      throw new Error(
        `Server error (500) when signing out.\n` +
        `This indicates a backend error. Check server logs.\n` +
        `Response: ${errorText.substring(0, 500)}`
      );
    }

    // Sign out should succeed (status may vary based on implementation)
    // 200 = success with body, 204 = success no content, 401 = already signed out or invalid token
    expect([200, 204, 401]).toContain(signOutResponse.status());
  });

  test('should require authentication for protected endpoints', async ({ request }) => {
    // Try to access a protected endpoint without token
    // Using /guilds endpoint which should require authentication
    const makeRequest = async () => {
      return await request.get(`${API_BASE_URL}/guilds`, {
        headers: {
          'Accept': 'application/json'
        }
      });
    };

    let response = await makeRequest();
    
    // Handle rate limiting
    if (response.status() === 429) {
      response = await handleRateLimit(response, makeRequest);
    }

    // Should be 401 for unauthenticated request, not 200 or 429
    if (response.status() !== 401) {
      const responseText = await response.text().catch(() => '');
      throw new Error(
        `Expected 401 for unauthenticated request but got ${response.status()}.\n` +
        `Response: ${responseText.substring(0, 500)}\n` +
        `The /guilds endpoint should require authentication.`
      );
    }
    expect(response.status()).toBe(401);
  });
});

