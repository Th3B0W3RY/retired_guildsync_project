# Quick Start Guide

## Getting Started in 5 Minutes

### 1. Install Dependencies
```bash
npm ci
npx playwright install
```

### 2. Start Your Rails Application

**Recommended: let the wrapper start Rails**
```bash
npm run test:with-server -- --yes --inline-server
```
When the target port is free, this prepares the test DB, seeds integration data, starts Rails, runs Playwright, and stops the server it started.

**Manual Rails test server:**
```bash
cd path/to/GuildSync/guildsync
RAILS_ENV=test INTEGRATION_TESTS=1 APP_URL=http://127.0.0.1:5000 PORT=5000 rails server -e test -p 5000
```

**Why test environment?**
- Uses separate test database (keeps development data safe)
- Allows easy database resets between test runs
- Matches CI/CD environment setup

**Alternative (Development Mode):**
If you prefer to use the development database:
```bash
cd path/to/GuildSync/guildsync
INTEGRATION_TESTS=1 APP_URL=http://127.0.0.1:5000 PORT=5000 rails server
```
Note: Tests will modify your development database in this mode.

### Environment files

- `../guildsync/.env` configures the Rails app/server process. Use `../guildsync/.env.example` as its template.
- `external_tests/.env` configures the Playwright/Node runner. Use `external_tests/.env.example` as its template.
- If the wrapper starts Rails and you change ports, keep `PORT`, `BASE_URL`, `API_BASE_URL`, and `APP_URL` aligned.

### 3. Set Up Test Data

**Option 1: Using Rake Task (Recommended)**
```bash
cd path/to/GuildSync/guildsync
rails test_data:setup -e test
```

**Note:** If you run `rails db:test:prepare -e test`, it will automatically run `test_data:setup` afterward.

**Option 2: Using Rails Runner**
```bash
cd path/to/GuildSync/guildsync
rails runner script/setup_test_data.rb
```

**Option 3: Manual Setup in Rails Console**
```ruby
# Create Free plan
PricingPlan.find_or_create_by!(name: "Free") do |plan|
  plan.price = 0
  plan.max_guilds = 1
  plan.max_members_per_guild = 10
  plan.active = true
end

# Create test user (with Discord auth method to bypass MFA)
User.find_or_create_by!(email: "test@example.com") do |user|
  user.username = "testuser"
  user.password = "password123"
  user.password_confirmation = "password123"
  user.auth_method = "discord"  # Bypasses MFA for faster tests
end

# Ensure test user has a subscription
user = User.find_by(email: "test@example.com")
plan = PricingPlan.find_by(name: "Free")
Subscription.find_or_create_by!(user: user, pricing_plan: plan) do |sub|
  sub.status = :active
end
```

**Verify Setup:**
```bash
rails test_data:verify -e test
```

**Important:** When running the server with `rails server -e test`, make sure to run the setup script in the same environment:
```bash
rails test_data:setup -e test
```

### 4. Verify Test Setup
```bash
npm run test:verify
```
This checks that your test user is configured correctly. Fix any setup issues before running other tests.

### 5. Run Your First Test
```bash
npm test
```

**Recommended for most users:** Use the centralized server-managed runner:
```bash
npm run test:with-server
```
This runs `scripts/run-tests-with-server.js`: when the target port is free it prepares the test database and seeds integration data, starts Rails if needed, runs tests, then stops the server it started (unless you pass `--keep-server`).

### 6. Run a Specific Test Suite
```bash
npm run test:auth
```

### 7. Run a Specific Test File
To run a single test file, pass the file path as an argument:
```bash
npm test -- tests/integration/auth/login.spec.js
```

Or use Playwright directly:
```bash
npx playwright test tests/integration/auth/login.spec.js --project=chromium
```

**Examples:**
- `npm test -- tests/integration/auth/mfa_setup.spec.js` - Run MFA setup tests
- `npm test -- tests/integration/api/auth.spec.js` - Run API auth tests
- `npm test -- tests/integration/setup/verify.spec.js` - Run setup verification tests

### 8. Run a Specific Test Case
To run a single test case within a file, use the `--grep` flag to match the test name:
```bash
npm test -- tests/integration/auth/login.spec.js --grep "should successfully login"
```

**Note:** The `--grep` flag uses regex matching, so you can use patterns like:
- `--grep "login"` - Matches any test with "login" in the name
- `--grep "^should successfully"` - Matches tests starting with "should successfully"
- `--grep "MFA|Two-Factor"` - Matches tests with either "MFA" or "Two-Factor"

### 9. Run Tests in Headed Mode
To run tests with a visible browser (useful for debugging), use the `--headed` flag:
```bash
npm test -- --headed
```

You can combine this with other options:
```bash
# Run a specific test case in headed mode
npm test -- tests/integration/auth/login.spec.js --grep "should successfully login" --headed
```

## Common Commands

- `npm test` - Run all tests (Chrome only by default)
- `npm run test:with-server` - Recommended centralized test runner (manages Rails server lifecycle automatically)
- `npm test -- --headed` - Run all tests with visible browser
- `npm test -- tests/integration/auth/login.spec.js` - Run a specific test file
- `npm test -- tests/integration/auth/login.spec.js --headed` - Run a specific test file with visible browser
- `npm test -- tests/integration/auth/login.spec.js --grep "test name"` - Run a specific test case
- `npm run test:headed` - Run all tests with visible browser (alternative to `npm test -- --headed`)
- `npm run test:debug` - Debug mode
- `npm run test:report` - View HTML test report
- `npm run test:summary` - Generate failure summary from last test run
- `npm run test:quiet` - Run tests with minimal console output
- `npm run test:firefox` - Run tests on Firefox
- `npm run test:webkit` - Run tests on Safari/WebKit
- `npm run test:all-browsers` - Run tests on all browsers
- `npm test -- --project=chromium` - Run tests on Chrome (explicit)
- `npm test -- --project=firefox` - Run tests on Firefox
- `npm test -- --project=webkit` - Run tests on Safari/WebKit

## Test Reports

After running tests, you'll find:

- **HTML Report**: `playwright-report/index.html` - Detailed interactive report (run `npm run test:report` to view)
- **Failure Summary**: `test-results/failures-summary.txt` - Concise list of failed tests
- **JSON Results**: `test-results/results.json` - Machine-readable test results

**Ctrl+C behavior (important):**
- `npm run test:report` starts a local report server and keeps running until you stop it with `Ctrl+C`.
- In `npm run test:with-server`, `Ctrl+C` triggers graceful cleanup first; press `Ctrl+C` again to force immediate exit if needed.

The failure summary is automatically generated after each test run and contains:
- Total test statistics
- List of failed tests with error messages
- File locations and line numbers
- Quick reference to the HTML report for full details

## Troubleshooting

### macOS: "Server already running" when it isn't (port 5000 / AirPlay Receiver)

On macOS Monterey and later, the AirPlay Receiver feature binds to port 5000 by default. Because `test:with-server` checks port 5000 with an HTTP probe before starting Rails, it can mistake ControlCenter's AirPlay listener for a running Rails server and skip its own startup — leaving tests pointed at a non-Rails process.

**Fix:** Disable AirPlay Receiver in **System Settings → General → AirDrop & Handoff** and uncheck **AirPlay Receiver**.

You can confirm the culprit with:
```bash
lsof -i :5000
```
If `ControlCenter` appears in that list, AirPlay Receiver is the cause.

### Seed users returning 401 after `rails db:reset`

If `db:reset` is run while the seed users already exist in the development database, the subsequent `test_data:setup` run will find them and skip creation — but their passwords may no longer match `password123` if the user records were originally created differently.

The seed script now calls `valid_password?` and updates the password if it doesn't match, so re-running the seed after a reset should self-heal:
```bash
npm run seed:dev   # or: npm run test:with-server (seed runs automatically)
```

## Next Steps

- Read [TESTING_PLAN.md](./TESTING_PLAN.md) for detailed test coverage
- Read [README.md](./README.md) for full documentation
- Customize tests in `tests/integration/` directory
