# AI_NOTE: Running Guildsync integration tests (fully automated)

**Date:** 2026-04-03  
**Audience:** Any AI agent or script (non-interactive OK)  
**Canonical workflow (option 1):** Let this repo start Rails in **test** so initializers and code always match what you just pulled.

These tests and helpers **change with the product**. If something fails, compare behaviour to the **GuildSync** Rails app (`guildsync/`) (routes, JSON, validations) before weakening assertions.

---

## 1. Paths and env

- **This repo:** `external_tests/` (where you run `npm`).
- **Rails app:** default `../../guildsync` relative to `external_tests/scripts/run-tests-with-server.js` (repo root: **GuildSync**). Override with **`GUILDSYNC_SERVER_DIR`** (absolute path) if your layout differs.
- **Default URL:** `http://localhost:5000` — the Guildsync Puma config uses **`PORT`** with default **5000** (`config/puma.rb`).
- **Env templates:** `external_tests/.env.example` is for Playwright/Node runner values such as **`BASE_URL`**, **`API_BASE_URL`**, **`TEST_MFA_SECRET`**, and reporter flags. `guildsync/.env.example` is for the Rails app/server process and production/development secrets. Do not merge them; only duplicate a value intentionally when the wrapper must pass it to the local Rails test server.

---

## 2. One-time / CI image setup

From **`external_tests/`**:

```bash
npm ci
npx playwright install chromium
```

From **`GuildSync/guildsync/`** (or via `GUILDSYNC_SERVER_DIR`):

```bash
RAILS_ENV=test bundle exec rails db:test:prepare
```

---

## 3. Automated run (preferred): script starts Rails

**Requirement:** Nothing else should be listening on the **same host:port** Playwright will use (default **5000** on `127.0.0.1`). If port **5000** is busy, use a free port and keep **`PORT`**, **`BASE_URL`**, and **`API_BASE_URL`** aligned, for example:

```bash
export PORT=5010
export BASE_URL=http://127.0.0.1:5010
export API_BASE_URL=http://127.0.0.1:5010/api/v1
export APP_URL=http://127.0.0.1:5010
```

From **`external_tests/`**:

```bash
# Full suite (Chromium). When the port is free, the script runs db:test:prepare + test_data:setup,
# then starts `rails server -e test`, then Playwright; stops the server after tests (unless --keep-server)
npm run test:with-server -- --yes --inline-server
```

Why **`--yes`:** Skips the interactive “Proceed?” prompt if stdin is not a TTY.  
Why **`--inline-server`:** Starts Rails in the **same** process tree (no extra GUI terminal) — best for agents and CI.

**Scoped runs** (same pattern; pass Playwright args after `--`):

```bash
npm run test:api:with-server -- --yes --inline-server
```

`CI=1` also skips the confirmation prompt (see `scripts/run-tests-with-server.js`).

---

## 4. If you must use an already-running server

`npm test` (without `:with-server`) only works if **`RAILS_ENV=test`** Rails is already up at **`BASE_URL`**. After **config/initializer** changes, that process must be **restarted** or you will see stale failures (e.g. JWT/HMAC). The wrapper script prints a **Tip** when it reuses an existing server.

---

## 5. Reading results

- Prefer **`test-results/results.json`** (e.g. `stats.unexpected`) for how many distinct runs failed; text summaries **repeat** retries.
- HTML report under **`playwright-report/`** when configured.

---

## 6. Cross-repo context for models

Longer historical rationale, prior QA notes, and AI-runner investigations belong in the separate knowledge-base repo:

`git@github.com:Th3B0W3RY/guildsync_knowledge_base.git`

---

## 7. Quick copy-paste (happy path)

```bash
cd /path/to/external_tests && npm ci && npx playwright install chromium
cd /path/to/external_tests && npm run test:with-server -- --yes --inline-server
```

The wrapper prepares the test database and seeds integration data before starting Rails when the target port is free (same as CI). You can still run `rails db:test:prepare` manually from **`guildsync/`** when debugging migrations.

Adjust `/path/to/...` and set **`GUILDSYNC_SERVER_DIR`** if the Rails root is not the default relative path.
