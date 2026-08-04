import { defineConfig, devices } from '@playwright/test';
import { getBaseURL } from './config/test-config.js';

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './tests/integration',
  
  /* Run tests in files in parallel */
  fullyParallel: true,
  
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  
  /* Retry failed tests — 2 on CI, 1 locally (Rails dev server under parallel load causes occasional flakiness) */
  retries: process.env.CI ? 2 : 1,

  /* Opt out of parallel tests on CI. */
  /* Note: Event creation tests use test.describe.serial() to run sequentially */
  /* because they require Discord bot connection (single account limitation) */
  workers: process.env.CI ? 1 : undefined,
  
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: [
    // Only auto-open HTML report for full suite runs
    // For single test runs, set open: 'never' to prevent auto-serving
    ['html', { 
      open: process.env.PLAYWRIGHT_FULL_SUITE === '1' ? 'on-failure' : 'never' 
    }],
    ['line'], // Less verbose console output (replaces 'list')
    ['json', { outputFile: 'test-results/results.json' }], // JSON for processing
    ['./reporters/failure-summary-reporter.js', { outputFile: 'test-results/failures-summary.txt' }] // Custom failure summary
  ],
  
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: getBaseURL(),
    
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',
    
    /* Screenshot on failure */
    screenshot: 'only-on-failure',
    
    /* Video on failure */
    video: 'retain-on-failure',
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },

    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },

    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },

    /* Test against mobile viewports. */
    // {
    //   name: 'Mobile Chrome',
    //   use: { ...devices['Pixel 5'] },
    // },
    // {
    //   name: 'Mobile Safari',
    //   use: { ...devices['iPhone 12'] },
    // },
  ],

  /* Run your local dev server before starting the tests */
  // webServer: {
  //   command: 'npm run start',
  //   url: getBaseURL(),
  //   reuseExistingServer: !process.env.CI,
  // },
});
