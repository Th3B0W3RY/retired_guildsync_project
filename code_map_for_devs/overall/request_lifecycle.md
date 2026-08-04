# Request lifecycle

**Last updated:** 2026-05-18 (**Gmail / Outlook OAuth** on **`public_page?`** + **`oauth_primary_auth?`** MFA short-circuit — align with **[authentication_mfa.md](authentication_mfa.md)**); 2026-04-06 (marketing **`/features/:slug`** on **`public_page?`**); 2026-04-02 (mega **#206** — **`ApplicationController`** filter order, **`public_page?`**, CSRF, **`UserActivityTracker`**)

## Router → controller

- **Source of truth:** `guildsync/config/routes.rb` (and `routes/*` if split).
- **Conventions:** RESTful resources for guilds, nested resources for polls, events, documents, etc. Admin under **`namespace :admin`**.

## `ApplicationController` — global stack

**File:** `guildsync/app/controllers/application_controller.rb`.

| Layer | What runs |
|-------|-----------|
| **CSRF** | **`protect_from_forgery with: :exception`**; **`rescue_from ActionController::InvalidAuthenticityToken`** → **`handle_csrf_error`** (JSON → **422** + **`controllers.application.csrf.error`**; HTML re-raises). |
| **`before_action :set_locale`** | See **[i18n.md](i18n.md)** — param → user / guest session → browser → default. |
| **`before_action :set_request_variant`** | HTML only; paths under **`/admin`** skipped. Sets **`request.variant = :mobile`** for phone-like **`User-Agent`** (iPhone/Android mobile, etc.) so templates can use **`*.html+mobile.erb`**. |
| **`before_action :configure_permitted_parameters`** | Devise only — username on sign-up / account update. |
| **`before_action :validate_session`** | **Unless** **`public_page?`**. Restores **`sign_in`** from **`session[:user_id]`** when Warden state was lost; clears stale **`user_signed_in?`** with nil user; ensures **`session[:user_id]`** backup for valid users. |
| **`before_action :authenticate_user!`** | **Unless** **`public_page?`**. |
| **`before_action :check_credentials_setup_required`** | **Unless** **`public_page?`**. **`MfaSetupController`** skips this; incomplete credentials before MFA setup are handled by **`MfaSetupController#check_profile_complete`** → **`complete_profile_path`**. |
| **`before_action :require_mfa_if_enabled`** | **Unless** **`public_page?`**. OAuth-primary **`auth_method`** short-circuits to verified session; MFA users need setup / session verification (30-minute window). Skipped on **`mfa_setup`**, **`mfa_verification`**, auth controllers, etc. (**`skip_mfa_check?`**). |
| **`before_action :ensure_fully_authenticated`** | **Unless** **`public_page?`**. Final guard: valid **`current_user`**, MFA session flags for users who are not OAuth-primary. |
| **`after_action :track_user_activity`** | **`if: :track_user_activity?`** — gated by **`UserActivity::RecordingPolicy`** (signed-in, **`GET`**/**`HEAD`**, non-XHR). **`UserActivity::Descriptor`** then decides per action: **skip** (OAuth `start`/`success`/`verify_session`, `home#dashboard`/`recent_activity`/`dashboard_stats`/`activity`, `sessions#new`/`create`/`destroy`), a no-link **"Signed in"** entry (OAuth `callback`), or a linkable page (friendly label from **`activity_label_for_tracking`** override or humanized controller name; **`link_path`** suppressed for `/auth`, `/login`, `/sign_in`, `/sign_out`, `/logout`). Records via **`UserActivityTracker.record(..., link_path:)`**; the feed (**`home#activity`** at **`/dashboard/activity`**) and dashboard widget link only when **`UserRecentActivity#linkable?`**. |

**Pundit:** **`include Pundit::Authorization`** — per-action **`authorize`** / **`policy_scope`** in controllers (see **[authorization.md](authorization.md)**).

### `public_page?` (no auth / MFA stack)

Marketing, auth flows (including **Discord**, **Gmail**, and **Outlook** OAuth start/callback/verify), Stripe + Discord webhooks, public roadmap/pricing, marketing **`HomepageFeaturesController#show`** (`/features/:slug`), document **share**, join links, etc. **Authoritative list** lives in **`ApplicationController#public_page?`** — extend there when adding a new unauthenticated surface; keep **[authentication_mfa.md](authentication_mfa.md)** in sync for MFA exceptions.

## Guild-scoped requests

- **Pattern:** **`params[:guild_id]`** or **`params[:id]`** identifies guild; **`set_guild`** (or equivalent) loads the record.
- **Access:** **`RequiresActiveGuildAccess`** concern and/or **`GuildPolicy`** — member or owner as required.
- **Plan gates:** Redirect to **`upgrade_pricing_path`** when **`current_user.plan_allows?(:feature)`** is false (e.g. message center, activity feed, documents, storage, **`members_gear`**).

## Response types

- **HTML** — Layouts **`application`**, **`application+mobile`** (see below); flash in layout.
  - **`request.variant` / `application+mobile`:** Selected from **User-Agent** in **`ApplicationController#set_request_variant`** (phone/tablet patterns), not from viewport width.
  - **Narrow desktop / resized window (`application.html.erb`):** Member chrome uses **`mobile-shell`** Stimulus with **`#desktop-sidebar-panel`** and Tailwind **`lg`**: below **1024px** width the sidebar is an off-canvas drawer and **`main-content-wrapper`** is **`ml-0 lg:ml-72`**; at **`lg+`** the sidebar remains a fixed column with the historical **`ml-72`** content offset. **`application.html+mobile.erb`** continues to use **`#mobile-sidebar-panel`** for the phone/tablet template variant only.
- **JSON** — Billing checkout, API-style controllers; CSRF still applies unless the route is API-only / webhook (see **`handle_csrf_error`**).

## Failure modes

| Failure | Typical behavior |
|---------|------------------|
| CSRF mismatch | JSON: **422** + message; HTML: exception / default Rails handling |
| Not signed in | Redirect to sign-in (**`return_to`** / Devise) |
| Stale / invalid session | **`validate_session`** / **`ensure_fully_authenticated`** → reset + login alert |
| MFA incomplete | Redirect to **`mfa_setup`** or **`mfa_verification`** |
| Not a guild member | Redirect to dashboard or **404** |
| Plan insufficient | Redirect to pricing (**`plan_entitlements.upgrade_required`**) |

## Spec pointers

- **`spec/requests/mfa_flow_spec.rb`**, **`spec/requests/mfa_complete_flow_spec.rb`** — session + MFA gates (**[authentication_mfa.md](authentication_mfa.md)**).
- **`spec/requests/applications_spec.rb`** — guild application HTTP surface (example of gated non-admin flow).
- **`spec/requests/*_spec.rb`** for major controllers; add a dedicated spec when changing **`validate_session`** / **`handle_csrf_error`** / **`public_page?`** behavior.
- Full-stack: **`external_tests/`** Playwright.

## Transport security

| Mechanism | Config | Notes |
|-----------|--------|-------|
| **HTTPS / TLS termination** | Reverse proxy (nginx / Caddy / Render) | App-level: **`config.assume_ssl = true`**, **`config.force_ssl = true`** (`config/environments/production.rb`). Non-HTTPS requests in production are redirected to HTTPS by Rails. |
| **HSTS** | **`config.ssl_options`** | Explicit policy: **`max-age=31536000`**, **`includeSubDomains`**, **`preload`** — eligible for browser preload lists. |
| **Secure cookies** | **`config/application.rb`** | Session cookie: **`secure: true`** (production), **`httponly: true`**, **`same_site: :lax`**. |
| **Redis TLS** | **`REDIS_URL=rediss://…`** | **`RedisConfig`** (`config/initializers/redis.rb`) detects the **`rediss://`** scheme and adds **`ssl: true`** + **`ssl_params`** to all Redis connections (cache, Sidekiq, Action Cable). Required for hosted Redis in production. |
| **Database TLS** | **`DATABASE_SSLMODE`** env var | Production **`database.yml`** defaults to **`sslmode: require`**. Override via **`DATABASE_SSLMODE`** (e.g. **`verify-full`** for strict cert validation, **`prefer`** for local dev without SSL). |
| **ActiveRecord field encryption** | **`config/initializers/active_record_encryption.rb`** | OAuth tokens, bot tokens, OTP secrets, messages, documents encrypted at rest — see [authentication_mfa.md](authentication_mfa.md). |

**Related:** [authentication_mfa.md](authentication_mfa.md), [authorization.md](authorization.md), [i18n.md](i18n.md), [app_flow_end_to_end.md](app_flow_end_to_end.md).
