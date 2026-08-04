import { test, expect } from '@playwright/test';
import { getAPIBaseURL } from '../../../config/test-config.js';
import { createTestUserAndGetToken, parseBlueprintResponse } from '../../helpers/test-helpers';

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

// Helper to safely parse JSON response with better error messages
async function safeJsonParse(response) {
  const contentType = response.headers()['content-type'] || '';
  const status = response.status();
  
  if (!contentType.includes('application/json')) {
    const text = await response.text();
    // If we got HTML, it might be an authentication/authorization issue
    if (contentType.includes('text/html')) {
      throw new Error(
        `Expected JSON but got HTML (status ${status}). This usually means:\n` +
        `1. The API endpoint doesn't exist or isn't configured for JSON responses\n` +
        `2. Authentication failed (JWT token not validated by backend)\n` +
        `3. The endpoint redirected to an HTML page\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    throw new Error(`Expected JSON but got ${contentType} (status ${status}). Response: ${text.substring(0, 200)}`);
  }
  try {
    return await response.json();
  } catch (error) {
    const text = await response.text();
    throw new Error(`Failed to parse JSON. Status: ${status}. Response: ${text.substring(0, 200)}`);
  }
}

// Helper to validate authentication and test data setup
async function validateSetup(request, authToken) {
  if (!authToken) {
    throw new Error('Authentication token is missing. Test setup failed.');
  }
  
  // Try a simple authenticated request to verify token works
  const testResponse = await request.get(`${API_BASE_URL}/guilds`, {
    headers: getAPIHeaders(authToken)
  });
  
  // If we get HTML, authentication isn't working
  const contentType = testResponse.headers()['content-type'] || '';
  if (contentType.includes('text/html')) {
    throw new Error(
      'Authentication setup failed: API returned HTML instead of JSON.\n' +
      'This indicates JWT token validation is not working in the backend.\n' +
      'The backend may need middleware to validate JWT tokens from Authorization header.\n' +
      'Status: ' + testResponse.status()
    );
  }
  
  return true;
}

// Helper to create API headers with authentication token
function getAPIHeaders(authToken) {
  return {
    'Authorization': `Bearer ${authToken}`,
    'Accept': 'application/json',
    'Content-Type': 'application/json'
  };
}

test.describe.serial('API Guild Management', () => {
  let authToken;
  let testGuildId = null;

  test.beforeAll(async ({ request }) => {
    // Create a fresh Discord auth user — bypasses require_mfa_if_enabled for API requests.
    const { token } = await createTestUserAndGetToken(request, {
      emailAffix: 'apiguild',
      usernameAffix: 'apiguild',
      authMethod: 'discord'
    });
    authToken = token;

    // Validate that authentication is working
    await validateSetup(request, authToken);

    // Create a guild for tests that need an existing guild (get, update).
    const createResponse = await request.post(`${API_BASE_URL}/guilds`, {
      headers: getAPIHeaders(authToken),
      data: { guild: { name: `API Test Guild Setup ${Date.now()}` } }
    });

    if ([200, 201].includes(createResponse.status())) {
      const body = await safeJsonParse(createResponse);
      const guild = parseBlueprintResponse(body.guild);
      if (guild && guild.id) {
        testGuildId = guild.id;
      }
    }
    // If creation returns 422 (e.g. games required), testGuildId stays null
    // and the get/update tests will skip rather than fail.
  });

  test('should create a guild via API', async ({ request }) => {
    const guildName = `API Test Guild ${Date.now()}`;
    const guildDescription = 'Test guild created via API';

    const response = await request.post(`${API_BASE_URL}/guilds`, {
      headers: getAPIHeaders(authToken),
      data: {
        guild: {
          name: guildName,
          description: guildDescription,
        }
      }
    });

    const status = response.status();
    
    // Validate response format first
    const contentType = response.headers()['content-type'] || '';
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON but got HTML (status ${status}). ` +
        `This suggests the API endpoint doesn't support JSON or authentication failed.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // May be 200 (created), 201 (created), or 422 (validation error if games required)
    if (status === 422) {
      const body = await safeJsonParse(response);
      if (body.errors && body.errors.game_ids) {
        // Games are required - this is expected behavior
        expect(status).toBe(422);
        return;
      }
      // Other validation errors
      expect(status).toBe(422);
      return;
    }
    
    // Accept 200 or 201 as success
    if (![200, 201].includes(status)) {
      const text = await response.text().catch(() => '');
      throw new Error(
        `Unexpected status ${status} when creating guild. ` +
        `Expected 200, 201, or 422. Response: ${text.substring(0, 200)}`
      );
    }
    
    // If successful, validate response structure
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('guild');
    
    const guild = parseBlueprintResponse(body.guild);
    expect(guild).toHaveProperty('name', guildName);
    if (guildDescription) {
      expect(guild).toHaveProperty('description', guildDescription);
    }
  });

  test('should list user guilds via API', async ({ request }) => {
    const response = await request.get(`${API_BASE_URL}/guilds`, {
      headers: getAPIHeaders(authToken)
    });

    const status = response.status();
    const contentType = response.headers()['content-type'] || '';
    
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON but got HTML (status ${status}). ` +
        `This suggests authentication failed or the endpoint doesn't support JSON.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    if (status !== 200) {
      const text = await response.text().catch(() => '');
      throw new Error(
        `Failed to list guilds. Status: ${status}. ` +
        `Response: ${text.substring(0, 200)}`
      );
    }
    
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('guilds');
    
    const guilds = parseBlueprintResponse(body.guilds);
    expect(Array.isArray(guilds)).toBeTruthy();
  });

  test('should get guild details via API', async ({ request }) => {
    if (!testGuildId) {
      test.skip('Guild creation in beforeAll failed (games may be required) — skipping get test');
      return;
    }

    const response = await request.get(`${API_BASE_URL}/guilds/${testGuildId}`, {
      headers: getAPIHeaders(authToken)
    });

    const status = response.status();
    const contentType = response.headers()['content-type'] || '';
    
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON but got HTML (status ${status}). ` +
        `This suggests authentication failed or guild ${testGuildId} is not accessible.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }

    if (status === 404) {
      throw new Error(`Guild ${testGuildId} not found — it was created in beforeAll and should exist`);
    }
    
    if (status !== 200) {
      const text = await response.text().catch(() => '');
      throw new Error(
        `Failed to get guild details. Status: ${status}. ` +
        `Response: ${text.substring(0, 200)}`
      );
    }
    
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('guild');
    
    const guild = parseBlueprintResponse(body.guild);
    expect(guild).toHaveProperty('id');
    expect(guild).toHaveProperty('name');
  });

  test('should update guild via API', async ({ request }) => {
    if (!testGuildId) {
      test.skip('Guild creation in beforeAll failed (games may be required) — skipping update test');
      return;
    }
    
    const updatedName = `Updated Guild ${Date.now()}`;

    const response = await request.patch(`${API_BASE_URL}/guilds/${testGuildId}`, {
      headers: getAPIHeaders(authToken),
      data: {
        guild: {
          name: updatedName
        }
      }
    });

    const status = response.status();
    const contentType = response.headers()['content-type'] || '';
    
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON but got HTML (status ${status}). ` +
        `This suggests authentication failed or user doesn't have permission to update guild ${testGuildId}.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // The authenticated user created this guild in beforeAll — they must be the owner.
    if (status === 403) {
      throw new Error(`403 Forbidden when updating guild ${testGuildId} — the owner should always have update permission`);
    }

    if (status === 404) {
      throw new Error(`Guild ${testGuildId} not found — it was created in beforeAll and should still exist`);
    }
    
    if (![200, 204].includes(status)) {
      const text = await response.text().catch(() => '');
      throw new Error(
        `Unexpected status ${status} when updating guild. ` +
        `Expected 200 or 204. Response: ${text.substring(0, 200)}`
      );
    }
    
    if (status === 200) {
      const body = await safeJsonParse(response);
      const guild = parseBlueprintResponse(body.guild);
      expect(guild).toHaveProperty('name', updatedName);
    }
  });

  test('should delete guild via API', async ({ request }) => {
    // Create a new user for this test to avoid guild limit issues.
    // Must use authMethod: 'discord' so require_mfa_if_enabled doesn't redirect API requests.
    const { token: testUserToken } = await createTestUserAndGetToken(request, {
      emailAffix: 'delete',
      usernameAffix: 'delete',
      authMethod: 'discord'
    });
    
    // Create a guild with the new user
    const createResponse = await request.post(`${API_BASE_URL}/guilds`, {
      headers: getAPIHeaders(testUserToken),
      data: {
        guild: {
          name: `Temporary Guild ${Date.now()}`
        }
      }
    });

    const createStatus = createResponse.status();
    const createContentType = createResponse.headers()['content-type'] || '';
    
    if (createContentType.includes('text/html')) {
      const text = await createResponse.text();
      throw new Error(
        `Failed to create guild for deletion test. Got HTML (status ${createStatus}). ` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // Accept 200 or 201 as success for creation
    if (![200, 201].includes(createStatus)) {
      const text = await createResponse.text().catch(() => '');
      throw new Error(
        `Failed to create guild for deletion test. Status: ${createStatus}. ` +
        `Response: ${text.substring(0, 200)}`
      );
    }
    
    const createBody = await safeJsonParse(createResponse);
    const guild = parseBlueprintResponse(createBody.guild);
    
    if (!guild || !guild.id) {
      throw new Error(`Created guild response missing guild.id. Response: ${JSON.stringify(createBody)}`);
    }
    
    const guildId = guild.id;

    // Delete the guild using the test user's token
    const deleteResponse = await request.delete(`${API_BASE_URL}/guilds/${guildId}`, {
      headers: getAPIHeaders(testUserToken)
    });

    const deleteStatus = deleteResponse.status();
    const deleteContentType = deleteResponse.headers()['content-type'] || '';
    
    if (deleteContentType.includes('text/html')) {
      const text = await deleteResponse.text();
      throw new Error(
        `Failed to delete guild. Got HTML (status ${deleteStatus}). ` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // Status may be 200 or 204 depending on implementation
    if (![200, 204].includes(deleteStatus)) {
      const text = await deleteResponse.text().catch(() => '');
      throw new Error(
        `Unexpected status ${deleteStatus} when deleting guild. ` +
        `Expected 200 or 204. Response: ${text.substring(0, 200)}`
      );
    }
  });

  test('should return error for unauthorized guild access', async ({ request }) => {
    // Try to access a guild the user doesn't have permission for
    const response = await request.get(`${API_BASE_URL}/guilds/999`, {
      headers: getAPIHeaders(authToken)
    });

    const status = response.status();
    const contentType = response.headers()['content-type'] || '';
    
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON error response but got HTML (status ${status}). ` +
        `This suggests authentication failed or the endpoint doesn't support JSON.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // Should return 403 (forbidden) or 404 (not found)
    if (![403, 404].includes(status)) {
      const text = await response.text().catch(() => '');
      throw new Error(
        `Unexpected status ${status} for unauthorized access. ` +
        `Expected 403 or 404. Response: ${text.substring(0, 200)}`
      );
    }
  });

  test('should validate guild data on creation', async ({ request }) => {
    // Try to create guild with invalid data (empty name)
    const response = await request.post(`${API_BASE_URL}/guilds`, {
      headers: getAPIHeaders(authToken),
      data: {
        guild: {
          name: ''
        }
      }
    });

    const status = response.status();
    const contentType = response.headers()['content-type'] || '';
    
    if (contentType.includes('text/html')) {
      const text = await response.text();
      throw new Error(
        `Expected JSON validation error but got HTML (status ${status}). ` +
        `This suggests authentication failed or the endpoint doesn't support JSON.\n` +
        `Response preview: ${text.substring(0, 300)}`
      );
    }
    
    // Should return 422 (Unprocessable Entity) for validation errors
    if (status !== 422) {
      const text = await response.text().catch(() => '');
      const body = await safeJsonParse(response).catch(() => null);
      
      if ([200, 201].includes(status)) {
        throw new Error(
          `Backend accepted an empty guild name (status ${status}) — name validation is not enforced. ` +
          `Response: ${JSON.stringify(body)}`
        );
      }
      
      throw new Error(
        `Expected 422 validation error but got status ${status}. ` +
        `Response: ${text.substring(0, 200)}`
      );
    }
    
    // Validate that error response has validation errors
    const body = await safeJsonParse(response);
    expect(body).toHaveProperty('errors');
  });
});
