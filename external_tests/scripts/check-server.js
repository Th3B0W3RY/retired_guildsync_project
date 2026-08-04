#!/usr/bin/env node

/**
 * Check if the Rails server is running on the configured port
 */

const http = require('http');
const { URL } = require('url');
const { getBaseURL } = require('../config/test-config');

const BASE_URL = getBaseURL();

function checkServer(url, timeout = 5000) {
  return new Promise((resolve) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
      path: '/',
      method: 'HEAD',
      timeout: timeout
    };

    const req = http.request(options, (res) => {
      resolve({ running: true, statusCode: res.statusCode });
    });

    req.on('error', (err) => {
      resolve({ running: false, error: err.message });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ running: false, error: 'Connection timeout' });
    });

    req.end();
  });
}

async function main() {
  const result = await checkServer(BASE_URL);
  
  if (result.running) {
    console.log(`✓ Server is running at ${BASE_URL} (status: ${result.statusCode})`);
    process.exit(0);
  } else {
    console.error(`✗ Server is not running at ${BASE_URL}`);
    console.error(`  Error: ${result.error}`);
    console.error(`\nPlease start the server first:`);
    console.error(`  cd ../guildsync`);
    console.error(`  bundle exec rails s`);
    process.exit(1);
  }
}

main();

