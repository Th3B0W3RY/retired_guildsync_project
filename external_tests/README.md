# GuildSync External Browser Tests

`external_tests/` contains GuildSync's Playwright browser integration suite. These tests run outside the Rails app process, start or target a real Rails server, and drive a real browser against `BASE_URL`.

They are end-to-end smoke and workflow tests for authentication, subscriptions, guild management, events, and API endpoints. They are not RSpec examples, not Capybara system specs, and not unit tests; Rails-side mocking and database behavior come from whichever Rails environment the server is running.

## Overview

The default wrapper command prepares the Rails test database, seeds integration users, starts a `RAILS_ENV=test` server when the target port is free, runs Playwright, and then stops the server.

## Test Structure

```
tests/integration/
├── api/              # API endpoint tests
├── auth/             # Authentication & MFA tests
├── events/           # Event management tests
├── guilds/           # Guild management tests
├── guild_members/    # Member management tests
└── subscriptions/   # Subscription & pricing tests
```

## Prerequisites

- Node.js 18+ and npm
- Ruby/Rails dependencies installed in `../guildsync`
- Playwright browsers installed with `npx playwright install`
- Local Postgres available for `RAILS_ENV=test`
- No other process listening on the selected `PORT` if you want the wrapper to prepare the database and start Rails

## Installation

```bash
npm ci
npx playwright install
```

Optional: create `external_tests/.env` from `.env.example` to override runner defaults. This file is for Playwright/Node values; Rails app/server values belong in `../guildsync/.env`.

```
PORT=5000
BASE_URL=http://localhost:5000
API_BASE_URL=http://localhost:5000/api/v1
APP_URL=http://localhost:5000
```

If the wrapper starts Rails for you and you change the port, keep `PORT`, `BASE_URL`, `API_BASE_URL`, and `APP_URL` aligned.

## Running Tests

**Recommended full run with Rails test server:**
```bash
npm run test:with-server -- --yes --inline-server
```

**All tests against an already-running server:**
```bash
npm test
```

**Specific suites:**
```bash
npm run test:auth          # Authentication tests
npm run test:subscriptions # Subscription tests
npm run test:guilds        # Guild tests
npm run test:members       # Member tests
npm run test:events        # Event tests
npm run test:api           # API tests
```

**Modes:**
```bash
npm run test:headed  # Visible browser
npm run test:debug    # Debug mode
npm run test:ui       # Interactive runner
npm run test:report   # View reports
```

## Test Configuration

Configured in `playwright.config.js`:
- Base URL: `http://localhost:5000` (via `BASE_URL` env var, configurable in `config/test-config.js`)
- Browsers: Chromium, Firefox, WebKit
- Retries: 2 on CI, 1 locally
- Screenshots/Videos: Captured on failure

`config/test-config.js` loads `external_tests/.env` explicitly so the Playwright config, server wrapper, setup verifier, and server checker use the same runner-side URL values.

## Test Data Setup

The wrapper runs `db:test:prepare` and `test_data:setup` automatically when it starts the Rails test server itself. The seed script creates the integration users used by this suite, including:

1. `test_data@example.com`
2. `test_data_no_sub@example.com`
3. `test_data_mfa@example.com`

**Rails setup (recommended):**
```bash
cd path/to/GuildSync/guildsync
rails test_data:setup -e test
```

## Writing New Tests

**Basic structure:**
```javascript
import { test, expect } from '@playwright/test';
import { helperFunction } from '../../helpers/test-helpers';

test.describe('Feature Name', () => {
  test('should do something', async ({ page }) => {
    // Test implementation
  });
});
```

**Test helpers available:**
- `generateTestEmail()`, `generateTestUsername()` - Unique test data
- `fillRegistrationForm()`, `fillLoginForm()` - Form helpers
- `expectNavigation()` - Navigation verification
- `loginUser()` - Login helper

**Best practices:**
- Use unique test data to avoid conflicts
- Wait for elements with `waitFor()` or `toBeVisible()`
- Keep tests independent and isolated
- Clean up test data when possible

## Continuous Integration

The root GitHub Actions workflow is `.github/workflows/ci_playwright_github_hosted.yml`. It installs Rails and Node dependencies, builds Rails assets, installs Chromium, then runs this suite from `external_tests/` with the Rails test server wrapper.

## Troubleshooting

**Timing issues:** Increase timeouts in test code
**MFA tests:** Install `otplib` for dynamic TOTP code generation
**Authentication:** Ensure test users exist with proper MFA setup
**Database conflicts:** Use unique identifiers and clean up test data

## Test Coverage

- ✅ User registration and authentication
- ✅ MFA setup and verification
- ✅ Password reset flow
- ✅ Free plan activation and paid plans
- ✅ Plan switching
- ✅ Guild creation and management
- ✅ Member invitations
- ✅ Event creation and participation
- ✅ API authentication and endpoints

## Contributing

When adding new tests:
1. Follow existing test structure
2. Use test helpers where possible
3. Keep tests independent
4. Update this README if adding new categories

## License

MIT
