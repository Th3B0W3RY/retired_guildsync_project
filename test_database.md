# Test database — local setup (GuildSync)

**Canonical filename:** this doc lives at the repo root as **`test_database.md`** (formerly `TEST_DATABASE.md` / `test_databse.md`). Links elsewhere should use that path.

Application code lives under **`guildsync/`**. Run all Rails and RSpec commands from that directory unless noted otherwise.

## Development vs test

| Mode | Typical command | Database |
|------|-----------------|----------|
| **Development** | `bin/dev` / `rails s` with default env | `development` entry in `config/database.yml` |
| **Tests** | `bundle exec rspec` | `test` entry in `config/database.yml` |

Most specs `require "rails_helper"`, which sets `ENV["RAILS_ENV"] ||= "test"` **before** Rails boots. The root **`.rspec`** file only `--require spec_helper`; `rails_helper` is per-spec (standard for request/model tests in this app).

Do not point **`RAILS_ENV=development`** at the test database, and do not run the normal human dev server against `RAILS_ENV=test`. Keep environments separate. The dedicated Playwright wrapper is the exception: it may start Rails with `RAILS_ENV=test` against a local `BASE_URL`/`APP_URL` so browser tests use the throwaway test DB.

## Environment variables

Resolved in **`guildsync/config/database.yml`**.

### Shared (often set in `guildsync/.env`)

| Variable | Role |
|----------|------|
| `DATABASE_NAME` | Dev DB name (default `guildsync_development`) |
| `DATABASE_USER` | PostgreSQL user |
| `DATABASE_PASSWORD` | PostgreSQL password |
| `DATABASE_HOST` | Host (e.g. `127.0.0.1`) |
| `DATABASE_PORT` | Port (default `5432`) |

### Test-specific overrides (optional)

If unset, test config falls back to the `DATABASE_*` values above.

| Variable | Role |
|----------|------|
| `TEST_DATABASE_NAME` | Test DB name. If unset, Rails uses `DATABASE_NAME` (defaulting to `guildsync_development`) then applies **`.gsub("_development", "_test")`** on that string (e.g. `guildsync_development` → `guildsync_test`). **Set `TEST_DATABASE_NAME` explicitly** if `DATABASE_NAME` does not contain the substring `_development` (otherwise the test DB name may not match what you expect). |
| `TEST_DATABASE_USER` | Defaults to `DATABASE_USER` |
| `TEST_DATABASE_PASSWORD` | Defaults to `DATABASE_PASSWORD` |
| `TEST_DATABASE_HOST` | Defaults to `DATABASE_HOST` |
| `TEST_DATABASE_PORT` | If unset, uses `DATABASE_PORT` (which defaults to **5432** in YAML via `ENV.fetch`) |

`guildsync/spec/rails_helper.rb` loads **`guildsync/.env`** before boot (same as tests reading Stripe/Discord stub keys) so these values apply to RSpec when present.

## Prepare the test database (schema)

From **`guildsync/`**:

```bash
bundle exec rails db:test:prepare
```

This creates or updates the test database schema (typically from `db/schema.rb`). Run it after pulling migrations or if specs abort with **`ActiveRecord::PendingMigrationError`**.

**One-shot dev setup** (development + test schema + assets) uses:

```bash
bin/setup
```

which runs `bin/rails db:prepare` then **`bin/rails db:test:prepare`**.

## Optional: create role and database (greenfield Postgres)

**`guildsync/script/setup_test_db.rb`** does **not** read `database.yml`; it uses its own env defaults, then runs `db:test:prepare` (which does use Rails config).

- Connects to **`postgres`** as superuser: `PGSUPERUSER` (default `postgres`), `PGSUPERPASS` (default **`ENV["PGPASSWORD"]`** or `postgres`).
- Ensures login role **`TEST_DATABASE_USER`** (default **`guildsync`**) with password **`TEST_DATABASE_PASSWORD`** (default **`guildsync`**).
- Ensures database **`TEST_DATABASE_NAME`** (default **`guildsync_test`** only — it does **not** apply the `DATABASE_NAME` + `_development` → `_test` rule from `database.yml`).

**Align env with Rails:** If your test DB name comes only from `DATABASE_NAME` + gsub (e.g. `guildsync_development` → `guildsync_test`), the script defaults still match. If you rely on a custom `DATABASE_NAME` without `_development`, set **`TEST_DATABASE_NAME`** (and user/password/host) the same in **`.env`** for both this script and Rails.

Host/port for the superuser connection: `TEST_DATABASE_HOST` (default **`127.0.0.1`**), `TEST_DATABASE_PORT` (default **`5432`** — note the script treats this as a string).

Unless `SKIP_TEST_DB_PREP=1`, the script then runs **`bundle exec rails db:test:prepare`** with `RAILS_ENV=test` (same as running that command yourself from **`guildsync/`**).

```bash
cd guildsync
ruby script/setup_test_db.rb
```

| Variable | Effect |
|----------|--------|
| `SKIP_TEST_DB_PREP=1` | Only ensures role/DB; skips `db:test:prepare` (run that manually afterward). |

## Run the test suite

```bash
cd guildsync
bundle exec rspec
```

`spec/spec_helper.rb` enables **SimpleCov** with a **60%** minimum line coverage by default. When you run only a few spec files, coverage can fail the run — set `SIMPLECOV_NO_MINIMUM=1` for that session if needed (see `spec/spec_helper.rb`).

After Rails loads, **`ActiveRecord::Migration.maintain_test_schema!`** in `spec/rails_helper.rb` keeps the test DB schema current (Rails will migrate or load schema as configured). If migrations are pending relative to `db/schema.rb`, it may abort with **`ActiveRecord::PendingMigrationError`** and tell you to run **`bundle exec rails db:test:prepare`**.

## Stuck connections / locks

If a run was interrupted and Postgres still holds connections to the test DB:

```bash
cd guildsync
bundle exec rails test_db:show_connections
bundle exec rails test_db:kill_connections
```

Non-interactive kill:

```bash
FORCE=1 bundle exec rails test_db:kill_connections
```

---

## Reference files (change only with deliberate review)

These define **how** the test database is selected, loaded, and cleaned up:

- `guildsync/config/database.yml`
- `guildsync/config/environments/test.rb`
- `guildsync/spec/rails_helper.rb` (schema maintenance, transactional fixtures)
- `guildsync/spec/spec_helper.rb` (RSpec + SimpleCov; loaded first via **`.rspec`** — **not** where DB config is read, but keep changes deliberate)
- `guildsync/bin/setup`
- `guildsync/script/setup_test_db.rb`
- `guildsync/lib/tasks/test_db_cleanup.rake`

Agents and contributors should **not** change test DB behavior or loading in passing edits; treat changes here as infrastructure and get explicit approval.

Workflow guardrails: **[`.cursor/WORKFLOWS.md`](.cursor/WORKFLOWS.md)** and **[`.cursor/rules`](.cursor/rules)** (see **[`AGENTS.md`](AGENTS.md)** for any AI agent) include a **test database guardrail**.

For **types of tests** (RSpec layout, RuboCop, Playwright, etc.), see **[`test_categories_and_types.md`](test_categories_and_types.md)**.
