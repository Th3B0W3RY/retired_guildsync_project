# Integration Testing Plan

Primary operational reference for the GuildSync Playwright integration test suite.
Historical coverage audits, skip root-cause notes, and old new-test backlogs live in `guildsync_knowledge_base` under `qa_notes/playwright/`.

---

## Prerequisites

- Node.js 18+ and npm installed
- Recommended: run via `npm run test:with-server -- --yes --inline-server` so the wrapper starts Rails with the same code under test.
- Manual server option: Rails app running with `INTEGRATION_TESTS=1` and `APP_URL` aligned to the Playwright `BASE_URL`.
- Default base URL: `http://localhost:5000` (override via `BASE_URL` in `external_tests/.env` or process env).
- Database seeded with pricing plans and at least one active game (see below)

Environment templates are intentionally split:

- `guildsync/.env.example` is for the Rails app/server process and app secrets.
- `external_tests/.env.example` is for the Playwright/Node runner (`BASE_URL`, `API_BASE_URL`, MFA test secret, reporter flags).

### Required seed data (Rails console)

Most tests create isolated users dynamically, but a few static records must exist:

```ruby
# Free pricing plan (required for all user creation)
PricingPlan.find_or_create_by!(name: "Free") do |p|
  p.price = 0
  p.max_guilds = 1
  p.max_members_per_guild = 25
  p.active = true
end

# At least one active game (required for guild creation form)
Game.find_or_create_by!(slug: "test-game") do |g|
  g.name        = "Test Game"
  g.description = "Default test game"
  g.active      = true
  g.ocr_config  = {}
end

# Seeded user for login/API tests that use fixed credentials
user = User.find_or_create_by!(email: "test_data@example.com") do |u|
  u.username              = "test_data"
  u.password              = "password123"
  u.password_confirmation = "password123"
  u.auth_method           = "discord"   # bypasses MFA in browser UI
end
user.ensure_free_plan_subscription

# Seeded MFA user for mfa_verification.spec.js
mfa_user = User.find_or_create_by!(email: "test_data_mfa@example.com") do |u|
  u.username              = "test_data_mfa"
  u.password              = "password123"
  u.password_confirmation = "password123"
  u.auth_method           = "mfa"
  u.mfa_enabled           = true
  u.mfa_verified          = true
end
mfa_user.ensure_free_plan_subscription
```

---

## Running tests

```bash
# Install dependencies
npm ci

# Run the full suite
npm test

# Run a single spec file
npx playwright test tests/integration/guilds/create.spec.js

# Run tests in headed mode (watch the browser)
npx playwright test --headed

# Interactive debug mode
npx playwright test --debug

# Open the last HTML report
npx playwright show-report
```

---

## Test user strategy

Most tests call `createTestUserAndGetToken(request, options)` in `beforeEach` / `beforeAll`.
This hits `POST /api/v1/auth/sign_up`, which only exists when `INTEGRATION_TESTS=1`.

| Option | Effect |
|--------|--------|
| `authMethod: 'discord'` | Sets `auth_method = 'discord'` on the record so `require_mfa_if_enabled` short-circuits. No real Discord OAuth happens. Use for all non-MFA browser tests. |
| `authMethod: 'mfa'` (default) | User requires MFA setup/verification. Use only when explicitly testing MFA flows. |
| `skip_mfa_verification: true` (default) | Rails-test-env flag that auto-verifies MFA on sign-up. Has no effect in development mode; `authMethod: 'discord'` is the reliable bypass in dev. |

---

## External dependencies

### Discord bot

`events/create.spec.js` and `guild_members/invite.spec.js` require a live Discord bot connected to the test guild. Both suites skip automatically when no bot is detected.

**To enable:** provision a test Discord application, store Rails bot credentials in `guildsync/.env`, store runner-only browser credentials such as `DISCORD_CREDENTIALS` in `external_tests/.env`, and call `connectDiscordBotToGuild()` from `helpers/discord-helpers.js` inside the relevant `beforeEach`. A dedicated test Discord server is recommended to avoid polluting a real server.

**Mocking strategy:** For tests that exercise form logic without needing real Discord delivery, the bot-connected check can be stubbed by adding a test-only bypass flag (similar to `INTEGRATION_TESTS=1`), letting the UI render without a real bot. Discord delivery can then be tested in a separate, slower suite.

### Stripe

Subscription tests that verify Stripe checkout, plan selection, or the billing portal require Stripe test-mode credentials. Without them those specific tests skip gracefully.

**To enable:** set Stripe test-mode Rails credentials in `guildsync/.env` and expose any Playwright-side guard values needed by the spec, such as `STRIPE_SECRET_KEY`, through `external_tests/.env` or process env. Use Stripe's test card `4242 4242 4242 4242` in automated tests.

**Webhook testing:** Stripe webhooks require a publicly reachable endpoint. Use the Stripe CLI (`stripe listen --forward-to localhost:5000/stripe/webhooks`) during local test runs.

### Discord OAuth (login/register via Discord)

Real Discord OAuth cannot be automated — it requires a human browser session and is protected against bots. Tests that need a "Discord-authenticated" user instead use `createTestUserAndGetToken` with `authMethod: 'discord'`, which sets the flag directly in the database without going through OAuth.

### OCR / gear management

The gear upload feature runs OCR on screenshots. OCR processing can take several seconds and depends on an external service or local binary.

**Strategy:** mock the OCR service response in fast tests (return a fixture hash) and test real OCR in a separate slow suite. Playwright's file upload API (`page.setInputFiles`) handles the screenshot input; the test only needs to verify the resulting gear record, not the OCR pipeline.

---

## CI integration

Tests should run:
- On every pull request (fast suite, mocks for Discord/Stripe)
- Nightly (full suite including real Discord and Stripe test-mode)
- Before every production deployment

Start the Rails server before the test run:
```bash
INTEGRATION_TESTS=1 RAILS_ENV=test APP_URL=http://127.0.0.1:5000 PORT=5000 bundle exec rails server -p 5000
```

---

## File structure

```
tests/
├── helpers/
│   ├── test-helpers.js       # createTestUserAndGetToken, expectNavigation, etc.
│   ├── otp-helpers.js        # TOTP generation for MFA tests
│   └── discord-helpers.js    # Discord bot connection helpers
├── pages/                    # Page Object Models
│   ├── LoginPage.js
│   ├── GuildCreationPage.js
│   ├── GuildsPage.js
│   ├── MfaSetupPage.js
│   ├── MfaVerificationPage.js
│   ├── GuildMemberInvitePage.js
│   └── EventCreationPage.js
└── integration/
    ├── api/                  # JWT-authenticated API endpoint tests
    ├── auth/                 # Login, registration, MFA, password reset
    ├── events/               # Event creation and participation
    ├── guilds/               # Guild creation and viewing
    ├── guild_members/        # Member invitations
    ├── setup/                # Environment health check
    └── subscriptions/        # Subscription, plan limits, Stripe flow
```
