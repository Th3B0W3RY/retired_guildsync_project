# Test categories and types (GuildSync)

Companion to **[`test_database.md`](test_database.md)** (Postgres test DB and RSpec env). This document lists **what kinds of tests and checks exist**, where they live, and what each major **RSpec area** is for.

Unless noted, the **Rails app** root is **`guildsync/`**.

### Keeping this file accurate (agents & contributors)

When you add or restructure automated tests—**new top-level `spec/` directory**, new **suite/category** (e.g. system specs, new E2E runner), new **CI job** that runs a different checker, or a new **default mocking** pattern in `spec/support/`—**update this file in the same change** so it stays the single map of test types and expectations. If a change only adds examples under an existing category, a doc update is optional unless behavior/mocking expectations change.

**Repo root:** [`test_categories_and_types.md`](test_categories_and_types.md) (tracked). Agent guardrail: **[`.cursor/WORKFLOWS.md`](.cursor/WORKFLOWS.md)** § Test categories doc guardrail; bootstrap: [`AGENTS.md`](AGENTS.md).

---

## Quick reference: suites and tools

| Kind | Tool / runner | Location | Typical command |
|------|----------------|----------|------------------|
| **Application automated tests** | **RSpec** (RSpec-Rails) | `guildsync/spec/` | `cd guildsync && bundle exec rspec` |
| **Code style (Ruby)** | **RuboCop** (rails-omakase config) | `guildsync/.rubocop.yml` | `cd guildsync && bin/rubocop` |
| **Security scan (Ruby/Rails)** | **Brakeman** | (gem + `guildsync/bin/brakeman`) | `cd guildsync && bin/brakeman --no-pager` |
| **Translation health** | **i18n-tasks** | `guildsync/config/i18n-tasks.yml` | `cd guildsync && bundle exec i18n-tasks health` |
| **Coverage (during RSpec)** | **SimpleCov** | `guildsync/spec/spec_helper.rb` | Runs with `rspec`; see `test_database.md` / `SIMPLECOV_NO_MINIMUM` |
| **Browser integration (E2E)** | **Playwright** (Node) | **`external_tests/`** | `cd external_tests && npm run test:with-server -- --yes --inline-server` (see README / `AI_NOTE_FOR_AI_RUNNERS.md`) |
| **JS build** | **esbuild** | `guildsync/package.json` | `npm run build` — **not** a test suite; bundles front-end |
| **GitHub → Discord automation** | Custom Actions workflow | `.github/workflows/discord_event_matrix_test.yml` | Manual dispatch; exercises repo events, **not** the Rails test suite |

There is **no** `npm test` (or Jest/Vitest) inside **`guildsync/`** today—only **`build`** / **`build:css`** scripts.

---

## RSpec (`guildsync/spec/`)

Stack: **RSpec**, **RSpec-Rails**, **FactoryBot**, **Faker**, **Pundit matchers**, **WebMock**, **Devise** integration helpers for request specs, **rails-controller-testing** gem (no `spec/controllers/` tree—behavior is covered mainly by **request** specs), **SimpleCov** on boot via `spec_helper`. There is **no** `spec/system/` folder and **no** examples using **`type: :system`** (Capybara system specs) in the current tree.

### Top-level directories — what they’re for

| Directory | Purpose |
|-----------|---------|
| **`spec/requests/`** | **HTTP / integration-style specs**: full stack through routing, controllers, auth, cookies, redirects. Subfolders group big areas (see below). Primary place for “does this page/route behave correctly?” |
| **`spec/models/`** | **ActiveRecord models**: validations, associations, scopes, callbacks (where not better covered at a higher level). |
| **`spec/services/`** | **Service objects** and non-trivial **lib-style** orchestration: Discord, OCR, billing helpers, landing CMS importers, etc. Often mirrors `app/services/`. |
| **`spec/jobs/`** | **ActiveJob** classes: enqueuing, execution with test adapter / Sidekiq-related behavior as configured. |
| **`spec/policies/`** | **Pundit** authorization: who may perform which actions on which records. |
| **`spec/channels/`** | **ActionCable** channels (e.g. loot rolls, alliance features). |
| **`spec/lib/`** | Code under **`app/lib`** and **`lib`** that isn’t a service: rake task specs, small libraries, initializer-adjacent helpers. |
| **`spec/lib/tasks/`** | **Rake tasks** invoked as documented in those specs. |
| **`spec/middleware/`** | **Rack middleware** (e.g. API logging). |
| **`spec/helpers/`** | **View helpers** (light use; most behavior is covered via requests or views indirectly). |
| **`spec/i18n/`** | **Locale fixtures**: missing keys, structural checks for JS/i18n strings used in views. |
| **`spec/assets/`** | Reserved for specs that need **asset** files or sprockets/propshaft behavior (may be empty). |
| **`spec/fixtures/`** | Static fixture files (`config.fixture_paths` in `rails_helper`). |
| **`spec/factories/`** | **FactoryBot** definitions for models / test data. |
| **`spec/support/`** | **Shared helpers, stubs, matchers**, WebMock configuration, custom RSpec setup. |

### Notable `spec/requests/` sub-areas

These are **not separate tools**—they organize the same **request spec** style by product area:

| Path under `requests/` | What it tends to cover |
|-------------------------|------------------------|
| **`admin/`** | Admin-only UI and endpoints (CMS, games, site settings, monitoring, etc.). |
| **`api/`** | **JSON API** (e.g. `api/v1/...`): mobile/API clients, token auth patterns. |
| **`discord/`** | OAuth, connections, Discord-related flows (sign-in, webhooks, interactions where exercised). |
| **`stripe/`** | Billing, checkout, subscription-related HTTP flows (with Stripe stubbing as configured). |
| **Root `google_oauth_account_creation_spec.rb`**, **`microsoft_oauth_account_creation_spec.rb`** | Gmail / Outlook OIDC: gated **`/create_account`** flow + login (provider HTTP stubbed; asserts consumer Microsoft authority for Outlook). |

Everything else directly under **`spec/requests/`** is still the same stack: full request cycle for marketing, guild, alliance, MFA, locale, storage, etc.

---

## Local dev vs CI vs production (expectations)

| Context | What you’re exercising | External APIs & paid services | Typical data store |
|--------|------------------------|--------------------------------|-------------------|
| **`RAILS_ENV=test` (RSpec)** | Ruby stack against **test Postgres**; no real deploy | **Not** production traffic. Stripe, most Discord HTTP, and outbound HTTP are **stubbed/blocked** by default (see below). Opt-in specs can hit **real S3** or **real Azure OCR** only with explicit env flags. | **Test DB** only (throwaway; transactional examples) |
| **Local `RAILS_ENV=development`** | Full app for humans; **`bin/dev`** / `rails s` | Uses **`.env`**: may point at Stripe test mode, real Discord dev app, local Typesense, etc.—**your** credentials and risk | **Development DB** |
| **CI (GitHub Actions)** | Same intent as local RSpec: **automated** `rspec` in Linux | Same **stub/mock** model as local test env; **secrets** only where the workflow defines them (still not “production Stripe”) | **CI Postgres** (and **Redis** where the workflow provides it—for code paths that talk to Redis) |
| **Production** | Live `guild-sync.net` (or your deploy) | **Real** Stripe, Discord, S3 (if configured), email delivery, Typesense, etc., per deploy env | **Production DB** |

**Playwright** (`external_tests/`) is different: it drives a **real browser** against a **URL you choose** (often `localhost` with `RAILS_ENV=test` or `development`). It does **not** go through WebMock; whatever the **Rails process** would call (DB, OAuth redirects, etc.) depends entirely on how you started the server.

**RuboCop / Brakeman / i18n-tasks** only read the repo (and i18n YAML); they do **not** boot the app or call production.

---

## Mocking, stubs, and real I/O (by type of test)

### RuboCop, Brakeman, i18n-tasks

| | Mocked / offline? | Notes |
|--|-------------------|--------|
| **RuboCop** | N/A (no runtime) | Parses Ruby; **no** DB, **no** HTTP. |
| **Brakeman** | N/A (no runtime) | Static security scan. |
| **i18n-tasks** | N/A | Reads locale files vs `I18n.t` usage; **no** external services. |

**Runs locally** (and in CI for RuboCop/Brakeman if that workflow is enabled). **Never** “production only.”

---

### RSpec — global defaults (`guildsync/spec/`)

These apply to **most** examples unless a spec opts out (metadata, env flags, or missing stubs).

| Concern | Default in specs | What is **not** mocked |
|---------|------------------|------------------------|
| **HTTP outbound** | **WebMock:** each example runs **`WebMock.disable_net_connect!(allow_localhost: true)`** unless metadata **`real_network: true`** skips that hook (`spec/support/webmock.rb`). Opt-in specs that need the real network also use **`WebMock.allow_net_connect!`** in an **`around`** block (e.g. real S3). | **PostgreSQL** is **real** (test database). Path through the stack is real Rails. |
| **Stripe** | Broad **HTTP stubs** for `api.stripe.com` on every example (`spec/support/stripe_stubs.rb`). | Same: DB and app code are real. |
| **Discord REST** | **Not** global. Specs that need Discord HTTP use **`include_context "Discord API stubs"`** (`spec/support/discord_api_stubs.rb`) to stub common Discord API URLs and env reads. Specs that call Discord without stubs must add their own **WebMock** expectations or they may fail with “connection refused / unstubbed request”. | OAuth **redirect flows** in request specs are still simulated (no real Discord login unless you build it). |
| **Action Mailer** | **`:test`** delivery method; emails go to **`ActionMailer::Base.deliveries`** (`config/environments/test.rb`). | No real SMTP. |
| **Active Job** | **`queue_adapter = :test`** (in-memory). Use **`perform_enqueued_jobs`** / matchers as needed. | Some code may still use **Sidekiq**’s client directly; CI often starts **Redis** for that. |
| **Active Storage** | Default service **`:test`** (disk) so uploads don’t need S3 (`config/environments/test.rb`). Request specs often **force** `:test` in an `around` block so `.env` doesn’t accidentally use S3 for baseline tests (`active_storage_uploads_spec.rb`). | Opt-in real S3: set **`REAL_S3_UPLOADS_IN_SPECS=1`**, required AWS bucket/key env vars, **`ACTIVE_STORAGE_SERVICE=amazon`** in test, and example metadata **`real_network: true`** (`active_storage_real_s3_uploads_spec.rb`). |
| **URL / host** | **`example.com`** for normal RSpec mailer and default URL options in test. When **`INTEGRATION_TESTS=1`** and **`APP_URL`** is present, Rails test URL defaults use `APP_URL` so Playwright redirects stay on the local test server. | — |
| **OCR (Azure / Surya / Tesseract paths)** | Typical **`GearOcrService`** specs **stub** engine classes so **no** API credits or Python are used (`gear_ocr_service_spec.rb`). | **`gear_ocr_service_real_images_spec`**: **skipped** unless **`ALLOW_REAL_OCR_IN_SPEC=1`** and Azure env + tooling are present (real credits possible). |
| **Search (Typesense)** | Many specs **stub** `TypesenseConfig.enabled?` or related clients; no live Typesense required for those. | If you add specs that don’t stub it, you may need a local Typesense or further mocks. |

**Summary:** RSpec **always** uses a **real test Postgres** and **real Rails code paths**; **external HTTP** is **blocked or stubbed** by default so local and CI runs don’t need production keys. **Production-only** behavior (live Stripe, live Discord app in prod mode, real customer data) is **not** what RSpec is designed to validate—use staging + manual QA or targeted integration tools.

---

### RSpec — what each **spec area** is responsible for (and usual I/O)

| Area | What it proves | Usually mocked / faked | Usually real |
|------|----------------|-------------------------|--------------|
| **`spec/requests/`** | HTTP status, redirects, session, HTML/JSON response shape, auth gates | Stripe HTTP; Discord when context/stubs present; Typesense when stubbed | Routing, controllers, views, params, **DB** |
| **`spec/models/`** | Validations, associations, DB constraints, callbacks | External services **only if** tests stub them | ActiveRecord + test DB |
| **`spec/services/`** | Business logic orchestration; Discord command dispatch; OCR pipeline **logic** with fake extractors | Stripe/Discord HTTP where stubs or doubles used; OCR backends stubbed in unit-style OCR specs | In-memory logic; often DB |
| **`spec/jobs/`** | Job arguments, idempotency hints, that the right service gets called | Downstream HTTP often stubbed per job spec | Job class behavior; may need Redis if job uses Sidekiq client |
| **`spec/policies/`** | Pundit `permit?` rules for roles/records | None (pure Ruby + test users/guilds) | Loaded models from factories |
| **`spec/channels/`** | ActionCable subscribe/broadcast rules | Depends on spec (often no external HTTP) | Channel Ruby code |
| **`spec/lib/`**, **`spec/middleware/`** | Rake tasks, middleware behavior | File system / HTTP as each test sets up | Ruby execution |
| **`spec/helpers/`** | Helper module output / edge cases | Rarely external HTTP | Ruby + any view context doubles |
| **`spec/i18n/`** | Keys exist per locale; JS-i18n placeholders | N/A | YAML + `I18n` |

---

### Playwright (`external_tests/`)

| | Mocked? | Notes |
|--|---------|--------|
| **Browser** | **Real** Chromium (etc.) | Not mocked. |
| **Your app** | **Real HTTP** to `BASE_URL` | Whatever environment the server was started with (test vs dev DB, real or fake OAuth, etc.). |
| **Stripe / Discord / third parties** | **Whatever the Rails app calls** | If the server uses **test** env with stubs, you still get “real” HTTP to localhost—the **app** might stub outbound. If you run against **development** with real keys, Playwright can trigger **real** side effects. |

**Expected to work locally** when the README’s prerequisites are met (Node, Playwright browsers, seeded server). **Not** a replacement for RSpec; **not** tied to WebMock in the test process (different process). For folder layout (`tests/integration/...`), see **`external_tests/README.md`**.

---

## RuboCop

- **Config:** `guildsync/.rubocop.yml` inherits **`rubocop-rails-omakase`** (Rails Omakase style).
- **CI (app submodule):** `guildsync/.github/workflows/ci.yml` runs `bin/rubocop -f github` on push/PR to **`guildsync`**’s default branch setup (see that file for triggers).
- **Not a runtime test:** static analysis only (style and some lint cops). **Mocks:** none (see **Mocking** § RuboCop / Brakeman / i18n-tasks above).

---

## Brakeman

- **Security-oriented** static analysis for Rails (SQL injection, XSS patterns, mass assignment, etc.—per Brakeman’s rules).
- **CI:** `guildsync/.github/workflows/ci.yml` runs `bin/brakeman --no-pager`.
- Treat reports as **signal**, not a substitute for RSpec or review. **Mocks:** none.

---

## i18n-tasks

- **Gem:** `i18n-tasks` in the Gemfile (`development, test` group).
- **Config:** `guildsync/config/i18n-tasks.yml`.
- **Use:** `bundle exec i18n-tasks health` (and other tasks per gem docs) to find missing/unused translation keys.
- **CI:** not wired in the workflows summarized above; run **locally** or add to CI if the team wants it gating merges.

---

## SimpleCov

- Runs when you run **RSpec** (required from `spec/spec_helper.rb`).
- **Not** a separate test type; it **measures** Ruby code exercised by examples. See **`test_database.md`** / **`SIMPLECOV_NO_MINIMUM`** for local partial-suite runs.

---

## CI context (monorepo)

- **Root repo** (this directory): **`.github/workflows/`** includes **RSpec** jobs that `cd guildsync`, use Postgres/Redis services, **`bundle exec rails db:test:prepare`**, then **`bundle exec rspec`** (see **`ci_rspec_github_hosted.yml`**). The **Build assets** steps in that workflow run **`yarn install --frozen-lockfile`**, **`yarn build:css`**, and **`yarn build`** inside **`guildsync/`** (even though the repo may use **`package-lock.json`** for local **npm** installs—match CI expectations if your job fails on lockfiles).
- **Playwright E2E on PRs:** **`ci_playwright_github_hosted.yml`** — **CI — E2E (Playwright)**. Same Postgres/Redis services; builds Rails assets; runs **`external_tests`** via **`npm run test:with-server -- --yes --inline-server`** with **`RAILS_ENV=test`**, **`INTEGRATION_TESTS=1`**, **`PORT=5000`**, and **`APP_URL=http://127.0.0.1:5000`**. The wrapper runs **`db:test:prepare`** and **`test_data:setup`** before starting Rails when the target port is free. Publishes **Playwright Results** to the PR checks UI (JUnit).
- Other workflows: **self-hosted RSpec** (`ci_rspec_self_hosted.yml`), **Discord/GitHub** automation (`discord_event_matrix_test.yml`), etc.
- **`guildsync/.github/workflows/ci.yml`**: **Brakeman + RuboCop** for the Rails app tree (nested GitHub config—useful if `guildsync` is used as its own repo). **Does not** run RSpec by itself.

Exact triggers (`pull_request`, `workflow_dispatch`, etc.) change over time—**always confirm in the YAML** before relying on them.

### When GitHub Actions is unavailable

If hosted minutes are exhausted or PR checks do not run, use local parity instead of assuming validation happened on GitHub:

- **Status:** [`.github/ci_availability.yml`](.github/ci_availability.yml) — update with [`guildsync/script/ci_status.sh`](guildsync/script/ci_status.sh)
- **Runbook:** [`.cursor/CI_AND_LOCAL_VALIDATION.md`](.cursor/CI_AND_LOCAL_VALIDATION.md) (decision hierarchy, tiers, PR template)
- **Runner:** `cd guildsync && unset BUNDLE_PATH && script/run_ci_local.sh` (full suite + rubocop + brakeman; `--e2e` for Playwright; `--i18n-scoped` for locale changes only — never `i18n-tasks health` as a gate)

This does not change RSpec, the test database, or spec files.

---

## Summary

- **Day-to-day app correctness:** **`bundle exec rspec`** under **`guildsync/`** (models, services, jobs, policies, channels, and mostly **request** specs). When GitHub CI is down, use **`script/run_ci_local.sh`** (see **When GitHub Actions is unavailable** above). **Real:** test Postgres + Rails. **Mocked by default:** most outbound HTTP; Stripe globally; Discord when stubbed; mail to `:test`; jobs to `:test` adapter.
- **Style + quick security signal:** **RuboCop** + **Brakeman** from **`guildsync/`** (offline analysis).
- **Translations:** **i18n-tasks** manually (or CI if added).
- **Coverage:** **SimpleCov** during RSpec.
- **Full browser flows:** **Playwright** in **`external_tests/`** with the app server up—**mocks match whatever server env you started**, not WebMock in the RSpec process.
- **`guildsync` npm scripts:** **build only**; no JavaScript unit test runner in that package today.
- **Production** is **not** covered by RSpec; it uses **real** services and **real** DB (no WebMock).

**Mocking rule of thumb:** In **RSpec**, assume **outbound HTTP is forbidden unless stubbed**; **Postgres test DB and Rails internals are real**. In **production**, the opposite: **real services and real DB**, with **no** WebMock.
