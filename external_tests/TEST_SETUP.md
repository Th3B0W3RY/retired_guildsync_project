# Test Setup Guide - Running Tests with Server

This guide explains how to run Playwright integration tests while the Rails server is running.

## Quick Start

### Option 1: Automatic Server Management (Recommended)

The easiest way to run tests is to let the scripts manage the server automatically:

```bash
# Run all tests (starts server if not running, stops it after tests)
npm run test:with-server

# Run specific test suite with server management
npm run test:auth:with-server
npm run test:subscriptions:with-server
npm run test:guilds:with-server
npm run test:members:with-server
npm run test:events:with-server
npm run test:api:with-server

# Run tests in headed mode (see browser)
npm run test:headed:with-server
```

**How it works:**
- Checks if the server is already running at `http://localhost:5000`
- If not running, starts the Rails server automatically
- Runs the Playwright tests
- Stops the server after tests complete (only if it was started by the script)
- If the server was already running, it leaves it running after tests

### Option 2: Manual Server Management

If you prefer to manage the server yourself:

1. **Start the Rails server manually:**
   ```bash
   cd ../guildsync
   bundle exec rails s
   ```

2. **In another terminal, check if server is running:**
   ```bash
   cd external_tests
   npm run test:check-server
   ```

3. **Run tests (server must be running):**
   ```bash
   npm test
   # or
   npm run test:auth
   npm run test:subscriptions
   # etc.
   ```

## Available Scripts

### Test Scripts (with automatic server management)
- `npm run test:with-server` - Run all tests with server management
- `npm run test:auth:with-server` - Run authentication tests
- `npm run test:subscriptions:with-server` - Run subscription tests
- `npm run test:guilds:with-server` - Run guild tests
- `npm run test:members:with-server` - Run member tests
- `npm run test:events:with-server` - Run event tests
- `npm run test:api:with-server` - Run API tests
- `npm run test:headed:with-server` - Run all tests in headed mode

### Test Scripts (manual server management)
- `npm test` - Run all tests (server must be running)
- `npm run test:auth` - Run authentication tests
- `npm run test:subscriptions` - Run subscription tests
- `npm run test:guilds` - Run guild tests
- `npm run test:members` - Run member tests
- `npm run test:events` - Run event tests
- `npm run test:api` - Run API tests
- `npm run test:headed` - Run tests in headed mode
- `npm run test:debug` - Run tests in debug mode
- `npm run test:ui` - Run tests with Playwright UI
- `npm run test:report` - View test report

### Utility Scripts
- `npm run test:check-server` - Check if the Rails server is running

## Configuration

### Server URL

By default, tests connect to `http://localhost:5000`. You can override this:

```bash
# Set custom base URL
BASE_URL=http://localhost:5001 npm run test:with-server
```

Or create a `.env` file in the `external_tests` directory:

```
PORT=5001
BASE_URL=http://localhost:5001
API_BASE_URL=http://localhost:5001/api/v1
APP_URL=http://localhost:5001
```

See `.env.example` for the full set of local overrides.

`external_tests/.env` is for Playwright/Node runner settings. Rails app/server settings and secrets belong in `../guildsync/.env` (see `../guildsync/.env.example`). When the wrapper starts Rails, it passes the runner environment through to that local server, so only put Rails values here when they are deliberately scoped to a test run.

**Note:** The default port is configured in `config/test-config.js` (currently set to 5000). To change it permanently, update `APP_PORT` in that file.

### Server Directory

The scripts look for the Rails server in:
```
../guildsync
```

If your server is in a different location, set `GUILDSYNC_SERVER_DIR` in `external_tests/.env` or the shell environment. Do not edit `scripts/run-tests-with-server.js` for a local checkout path.

## Troubleshooting

### Server Won't Start

If the automatic server start fails:

1. **Check if the server directory exists:**
   ```bash
   ls ../guildsync
   ```

2. **Verify Rails is installed:**
   ```bash
   cd ../guildsync
   bundle exec rails --version
   ```

3. **Check database is set up:**
   ```bash
   cd ../guildsync
   bundle exec rails db:migrate
   ```

4. **Start server manually to see errors:**
   ```bash
   cd ../guildsync
   bundle exec rails s
   ```

### Tests Fail to Connect

1. **Check if server is running:**
   ```bash
   npm run test:check-server
   ```

2. **Verify the port:**
   - Default is `http://localhost:5000`
   - Check if another process is using port 5000
   - Update `BASE_URL` if server is on a different port
   - Port is configured in `config/test-config.js` (set `APP_PORT` to change default)

3. **Check server logs:**
   - If server was started manually, check the terminal output
   - Look for errors in `guildsync/log/test.log` when `RAILS_ENV=test`, or `guildsync/log/development.log` when running against development

### Server Doesn't Stop After Tests

If you used `test:with-server` and the server doesn't stop:

1. The server might have been already running before the script started
2. The script only stops servers it started
3. To stop manually, find the process:
   ```bash
   # Find Rails server process
   lsof -i :5000
   # or
   ps aux | grep rails
   ```

## Best Practices

1. **For Development:**
   - Keep the server running manually in one terminal
   - Use regular test commands (`npm test`, `npm run test:auth`, etc.)
   - This is faster for iterative testing

2. **For CI/CD or One-off Runs:**
   - Use `test:with-server` scripts
   - Let the script manage the server lifecycle
   - Ensures a clean state for each test run

3. **For Debugging:**
   - Use `npm run test:debug` or `npm run test:ui`
   - Start server manually so you can see server logs
   - Use `npm run test:headed` to see browser actions

## Example Workflow

### Daily Development Workflow

```bash
# Terminal 1: Start server
cd ../guildsync
bundle exec rails s

# Terminal 2: Run tests as you develop
cd external_tests
npm run test:auth          # Quick test
npm run test:subscriptions # Test specific feature
npm run test:headed        # See what's happening
```

### Full Test Run

```bash
# One command, server managed automatically
cd external_tests
npm run test:with-server
```

### Continuous Testing

```bash
# Watch mode (if you add a watch script)
npm run test:with-server -- --watch

# Or use Playwright UI for interactive testing
npm run test:ui
```
