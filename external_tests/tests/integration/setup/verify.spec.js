/**
 * Setup Verification Tests
 * These tests verify that the test environment is properly configured.
 * Other tests should depend on these passing.
 */

import { test, expect } from '@playwright/test';
import { getBaseURL, getAPIBaseURL } from '../../../config/test-config.js';
import { LoginPage } from '../../pages';

const API_BASE_URL = getAPIBaseURL();
const BASE_URL = getBaseURL();

test.describe('Test Environment Setup', () => {
  test('should have Rails server running', async ({ request }) => {
    const response = await request.get(`${BASE_URL}/up`);
    expect(response.status()).toBe(200);
  });

  test('should have test user configured for API', async ({ request }) => {
    const email = 'test_data@example.com';
    const password = 'password123';
    const sign_in_url = `${API_BASE_URL}/auth/sign_in`;
    console.log(`Posting to ${sign_in_url}`);

    const response = await request.post(sign_in_url, {
      data: {
        user: {
          email,
          password
        }
      }
    });

    // Should return 200 (success) or 401 (invalid credentials)
    // If 401, the test user doesn't exist or password is wrong
    if (response.status() === 401) {
      const body = await response.json().catch(() => ({}));
      throw new Error(
        `Test user setup issue: API authentication failed.\n` +
        `Email: ${email}\n` +
        `Error: ${body.error || 'Invalid email or password'}\n` +
        `\nPlease ensure test user exists in Rails console:\n` +
        `User.find_or_create_by!(email: "${email}") do |u|\n` +
        `  u.username = "testuser"\n` +
        `  u.password = "password123"\n` +
        `  u.password_confirmation = "password123"\n` +
        `  u.auth_method = "discord"\n` +
        `end`
      );
    }

    expect([200, 201]).toContain(response.status());
    const body = await response.json();
    
    // If MFA is required, that's okay - user exists
    // But ideally test user should have auth_method: "discord" to bypass MFA
    if (body.mfa_required) {
      console.warn('Warning: Test user requires MFA. Consider setting auth_method: "discord" for faster tests.');
    } else {
      expect(body).toHaveProperty('token');
    }
  });

  test('should have test user configured for web login', async ({ page }) => {
    const email = 'test_data_mfa@example.com';
    const password = 'password123';

    const loginPage = new LoginPage(page);
    
    try {
      // Allow MFA for this test user (test_data_mfa@example.com has MFA enabled)
      await loginPage.loginAndWaitForSuccess(email, password, { allowMFA: true });
      
      // If we get here, login worked (even if MFA is required)
      const currentUrl = page.url();
      expect(currentUrl).not.toContain('/login');
    } catch (error) {
      // If login fails, provide helpful error message
      throw new Error(
        `Test user setup issue: Web login failed.\n` +
        `Email: ${email}\n` +
        `Error: ${error.message}\n` +
        `\nPlease ensure test user exists in Rails console:\n` +
        `User.find_or_create_by!(email: "${email}") do |u|\n` +
        `  u.username = "testuser"\n` +
        `  u.password = "password123"\n` +
        `  u.password_confirmation = "password123"\n` +
        `  u.auth_method = "discord"\n` +
        `end\n` +
        `\nAlso ensure user has a subscription:\n` +
        `plan = PricingPlan.find_or_create_by!(name: "Free") do |p|\n` +
        `  p.price = 0\n` +
        `  p.max_guilds = 10\n` +
        `  p.active = true\n` +
        `end\n` +
        `Subscription.find_or_create_by!(user: user, pricing_plan: plan)`
      );
    }
  });
});

