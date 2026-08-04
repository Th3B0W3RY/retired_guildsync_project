/**
 * OTP Helper Functions
 * Provides utilities for generating TOTP codes for MFA testing
 */

// Speakeasy uses CommonJS, so we need to import it differently
import speakeasy from 'speakeasy';

/**
 * Generate a TOTP code from a secret
 * @param {string} secret - Base32 encoded OTP secret
 * @returns {string} 6-digit OTP code
 */
export function generateOTP(secret) {
  if (!secret) {
    throw new Error('OTP secret is required. Set TEST_MFA_SECRET environment variable or pass secret directly.');
  }
  
  // Ensure secret is properly formatted (remove spaces, convert to uppercase)
  const cleanSecret = secret.replace(/\s+/g, '').toUpperCase();
  
  // Generate TOTP token using speakeasy
  return speakeasy.totp({
    secret: cleanSecret,
    encoding: 'base32'
  });
}

/**
 * Get the test user's OTP secret from environment or return default test secret
 * @returns {string} Base32 encoded OTP secret
 */
export function getTestUserSecret() {
  // Check environment variable first
  if (process.env.TEST_MFA_SECRET) {
    return process.env.TEST_MFA_SECRET;
  }
  
  // Fallback to a test secret (you should replace this with actual test user's secret)
  // This is a known test secret that can be used for testing
  // In production, you'd get this from your test data setup
  const defaultTestSecret = process.env.TEST_MFA_SECRET_DEFAULT || 'JBSWY3DPEHPK3PXP';
  
  console.warn('Using default test OTP secret. Set TEST_MFA_SECRET env var for production-like testing.');
  
  return defaultTestSecret;
}

/**
 * Generate OTP code for the test MFA user
 * @returns {string} 6-digit OTP code
 */
export function generateTestUserOTP() {
  const secret = getTestUserSecret();
  return generateOTP(secret);
}

/**
 * Verify an OTP code against a secret
 * @param {string} token - OTP code to verify
 * @param {string} secret - Base32 encoded OTP secret
 * @returns {boolean} True if code is valid
 */
export function verifyOTP(token, secret) {
  if (!secret) {
    return false;
  }
  
  const cleanSecret = secret.replace(/\s+/g, '').toUpperCase();
  
  try {
    return speakeasy.totp.verify({
      secret: cleanSecret,
      encoding: 'base32',
      token: token,
      window: 2 // Allow 2 time steps (60 seconds) of tolerance
    });
  } catch (error) {
    console.error('OTP verification error:', error);
    return false;
  }
}

/**
 * Get the OTP secret for a specific test user
 * This can be extended to support multiple test users
 * @param {string} email - User email
 * @returns {string} Base32 encoded OTP secret
 */
export function getUserSecret(email) {
  // Map of test users to their secrets
  // In a real scenario, you might fetch this from an API or test database
  const userSecrets = {
    'test_data_mfa@example.com': process.env.TEST_MFA_SECRET || getTestUserSecret(),
    // Add more test users as needed
  };
  
  return userSecrets[email] || getTestUserSecret();
}

/**
 * Generate OTP code for a specific user
 * @param {string} email - User email
 * @returns {string} 6-digit OTP code
 */
export function generateUserOTP(email) {
  const secret = getUserSecret(email);
  return generateOTP(secret);
}
