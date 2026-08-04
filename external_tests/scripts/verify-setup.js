#!/usr/bin/env node

/**
 * Verify that the test setup is working correctly
 * Checks Node.js, Playwright, server connection, and test files
 */

const { spawn } = require('child_process');
const http = require('http');
const { URL } = require('url');
const fs = require('fs');
const path = require('path');
const { getBaseURL, APP_PORT } = require('../config/test-config');

const BASE_URL = getBaseURL();

console.log('🔍 Verifying Test Setup...\n');

// Check Node.js version
console.log('1. Checking Node.js...');
const nodeVersion = process.version;
console.log(`   ✓ Node.js ${nodeVersion} is installed\n`);

// Check Playwright
console.log('2. Checking Playwright...');
const playwrightCheck = spawn('npx', ['playwright', '--version'], { shell: true });
playwrightCheck.stdout.on('data', (data) => {
  console.log(`   ✓ Playwright ${data.toString().trim()} is installed\n`);
});
playwrightCheck.stderr.on('data', () => {});
playwrightCheck.on('close', (code) => {
  if (code !== 0) {
    console.log('   ✗ Playwright not found. Run: npm ci\n');
  }
});

// Check server connection
console.log('3. Checking server connection...');
const parsedUrl = new URL(BASE_URL);
const options = {
  hostname: parsedUrl.hostname,
  port: parsedUrl.port || APP_PORT,
  path: '/',
  method: 'HEAD',
  timeout: 3000
};

const req = http.request(options, (res) => {
  console.log(`   ✓ Server is running at ${BASE_URL} (status: ${res.statusCode})\n`);
  checkTestFiles();
});

req.on('error', (err) => {
  console.log(`   ✗ Server is not running at ${BASE_URL}`);
  console.log(`     Error: ${err.message}`);
  console.log(`     Start server: cd ../guildsync && bundle exec rails s\n`);
  checkTestFiles();
});

req.on('timeout', () => {
  req.destroy();
  console.log(`   ✗ Server connection timeout`);
  console.log(`     Make sure server is running at ${BASE_URL}\n`);
  checkTestFiles();
});

req.end();

// Check test files
function checkTestFiles() {
  console.log('4. Checking test files...');
  const testDir = path.join(__dirname, '../tests/integration');
  
  if (!fs.existsSync(testDir)) {
    console.log('   ✗ Test directory not found\n');
    return;
  }
  
  const testSuites = fs.readdirSync(testDir, { withFileTypes: true })
    .filter(dirent => dirent.isDirectory())
    .map(dirent => dirent.name);
  
  if (testSuites.length === 0) {
    console.log('   ✗ No test suites found\n');
    return;
  }
  
  console.log(`   ✓ Found ${testSuites.length} test suite(s):`);
  testSuites.forEach(suite => {
    const suitePath = path.join(testDir, suite);
    const testFiles = fs.readdirSync(suitePath)
      .filter(file => file.endsWith('.spec.js') || file.endsWith('.test.js'));
    console.log(`     - ${suite} (${testFiles.length} test file(s))`);
  });
  
  console.log('\n✅ Setup verification complete!');
  console.log('\n📝 Quick Start:');
  console.log('   npm run test:with-server        # Run all tests with auto server management');
  console.log('   npm run test:check-server       # Check if server is running');
  console.log('   npm run test:auth:with-server   # Run specific test suite');
  console.log('\n📚 See TEST_SETUP.md for more details\n');
}
