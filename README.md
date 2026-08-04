# GuildSync (retired archive)

This repository is a retired, read-only snapshot of the GuildSync application.
It is preserved for reference and is not an actively maintained production
release. Review dependencies, configuration, and security controls independently
before reusing or deploying any part of it.

- **Production deploy:** bare-metal / VM using **[`deploy/deploy.sh`](deploy/deploy.sh)** (git checkout, `bundle`, `rails db:migrate`, assets) and **systemd** units under [`deploy/`](deploy/). The app is **not** shipped via Docker or Kamal in this workflow.
- **AI coding agents (any tool):** see [`AGENTS.md`](AGENTS.md) for archive-safe guidance.
- **Historical artifacts:** see [`docs/KNOWLEDGE_BASE.md`](docs/KNOWLEDGE_BASE.md) for the public archive boundary.
- **Rails test database (Postgres env, `db:test:prepare`, RSpec):** see [`test_database.md`](test_database.md).
- **What tests and linters exist (RSpec, RuboCop, Brakeman, Playwright, etc.):** see [`test_categories_and_types.md`](test_categories_and_types.md).
- Application code is under **`guildsync/`**.
- **Web OAuth (optional):** for **Gmail** and **Outlook** sign-in and gated **`/create_account`** completion, set **`GOOGLE_CLIENT_ID`**, **`GOOGLE_CLIENT_SECRET`**, **`MICROSOFT_CLIENT_ID`**, and **`MICROSOFT_CLIENT_SECRET`**. Register redirect URIs **`…/auth/google/callback`** and **`…/auth/microsoft/callback`** with each provider (host from app **`default_url_options`**). See **[`code_map_for_devs/overall/authentication_mfa.md`](code_map_for_devs/overall/authentication_mfa.md)**.
