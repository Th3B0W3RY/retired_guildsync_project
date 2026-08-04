/**
 * Test Configuration Constants
 * Centralized configuration for test suite
 */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

// Application port - update this when the application port changes
const APP_PORT = 5000;

// Base URL construction helper
function getBaseURL() {
  return process.env.BASE_URL || `http://localhost:${APP_PORT}`;
}

// API Base URL construction helper
function getAPIBaseURL() {
  const baseURL = getBaseURL();
  return process.env.API_BASE_URL || `${baseURL}/api/v1`;
}

// CommonJS export for scripts
module.exports = {
  APP_PORT,
  getBaseURL,
  getAPIBaseURL
};
