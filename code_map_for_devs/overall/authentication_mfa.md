# Authentication and MFA

**Last updated:** 2026-05-25 (**Gmail / Outlook OAuth:** login first matches provider UID, then safely auto-links an existing completed, confirmed, signup-email-verified GuildSync account when the provider returns the same verified email); 2026-05-18 (**Gmail / Outlook OAuth:** web routes **`/auth/google`**, **`/auth/microsoft`** mirror Discord for **gated** account creation (after email verify + backup code) and for **login**; **`User#oauth_primary_auth?`** covers Discord, Google, and Microsoft for MFA session skips — see **`OidcUserAuthBaseController`**, **`SignupGate`**, **`OidcOAuthPrimarySession`**. **Admin console:** **`Admin::SessionsController`** compares **`ADMIN_EMAIL`** / **`ADMIN_EMAILS`** / **`ADMIN_PASSWORD`** from ENV with **`.strip`** on password and normalized email list so production secrets with stray newlines still match; login form **`data-turbo="false"`** — see **`code_map_for_devs/systems/admin_dashboard.md`** + **`spec/requests/admin/sessions_spec.rb`**. **Session cookie:** **`CookieStore`** **`domain: nil`** in **development**/**test** for Safari **`localhost`** — **`config/application.rb`**. **Sign-in:** **`login_path(email_login: 1)`** vs OAuth providers — **`sessions_new_email_login_spec`**. Mega **#194** baseline.)

## Request pipeline (signed-in member app)

**`ApplicationController`** runs this chain on **non-**`public_page?` requests:

1. **`validate_session`** — Restores Warden from **`session[:user_id]`** when the cookie exists but Warden state was lost (e.g. post-OAuth redirect); clears invalid sessions.
2. **`authenticate_user!`** (Devise)
3. **`check_credentials_setup_required`** — Runs for signed-in, non-public requests (early exit for **`profile_completion`**). **`MfaSetupController`** **skips** this callback; profile completeness before **`GET /mfa/setup`** is enforced in **`MfaSetupController#check_profile_complete`** (covers OAuth-primary users with placeholder Discord email, etc.).
4. **`require_mfa_if_enabled`** — **OAuth-primary** users (`oauth_primary_auth?`): sets **`session[:mfa_verified]`** / **`session[:mfa_verified_at]`** and returns. Email/MFA users: incomplete MFA → **`mfa_setup_path`**; missing session MFA → **`mfa_verification_path(return_to: request.path)`**; session older than **30 minutes** → re-verify.
5. **`ensure_fully_authenticated`** — Final guard: same OAuth-primary vs MFA branching; **`mfa_verified_for_session?`** must pass for non-OAuth-primary users.
6. **`ensure_verified_real_email!`** (**`EnsureVerifiedRealEmail`**) — For HTML/Turbo requests, signed-in users without **`User#verified_real_email?`** (e.g. `@discord.guildsync.local` or missing **`signup_email_verified_at`**) are redirected to **`profile_settings_path`** except on an allowlisted set of controllers (`settings`, `profiles`, `profile_email_verifications`, signup/MFA/Devise recovery, etc.). **JSON:** **`controller_path` under `api/`** is skipped so v1 clients are not forced through the browser profile flow. **Profile email confirm:** **`GET /profile/email/verify?token=`** applies the pending address from **`signup_email_verifications`** (rows with **`user_id`**).

**`skip_mfa_check?`** is **`true`** for controllers **`mfa_setup`**, **`mfa_verification`**, **`sessions`**, **`registrations`**, **`passwords`**, **`discord_user_auth`**, **`google_user_auth`**, **`microsoft_user_auth`**, **`profile_completion`**, and for **`public_page?`**.

## `public_page?` (high level)

Treat as a **whitelist** of unauthenticated (or partially authenticated) surfaces: e.g. **`home#landing`/`pricing`**, **`settings#release_notes`**, **`roadmap`**, **`pricing#public_pricing`/`select_plan`**, **`sessions`/`registrations`/`passwords`**, **`backup_codes#verify`**, **`recoveries`**, **`discord_user_auth`** **`start`/`callback`/`verify_session`/`success`**, **`google_user_auth`** / **`microsoft_user_auth`** **`start`/`callback`/`verify_session`** (OIDC, aligned with Discord), **`stripe_webhooks#create`**, **`discord_webhooks`**, **`discord_event_signups#webhook`**, document **`guild_documents#share`**, **`join#show`**. **Risk:** widening this list by mistake exposes data — keep changes review-heavy.

Full conditionals live in **`ApplicationController#public_page?`**.

## MFA concern — `mfa_verified_for_session?`

**`MfaVerification`** (included in **`ApplicationController`**) exposes **`helper_method :mfa_verified_for_session?`**.

| User state | Result |
|------------|--------|
| Not signed in | **`false`** |
| **`auth_method` OAuth primary** (Discord, Google, Microsoft) | **`true`** (OAuth treated as verified; no TOTP window) |
| Else | Requires **`mfa_enabled?`**, **`mfa_verified?`**, **`session[:mfa_verified]`**, and **`session[:mfa_verified_at]`** within **30 minutes** |

**Discord users** still enter **`mfa_setup`** / **`mfa_verification`** controllers when enabling optional TOTP; layouts use **`mfa_flow_shell`** so the **member sidebar does not render** during that flow (see below). The same applies to **Google** and **Microsoft** OAuth-primary users.

## Email / password (Devise)

- **`devise_for :users`** skips default **`sessions`**, **`registrations`**, **`passwords`**; custom routes under **`as :user`** (**`/login`**, **`/sign_up`**, **`/password/*`**, **`/mfa/*`**).
- Controllers: **`SessionsController`**, **`RegistrationsController`**, **`PasswordsController`** — password success paths coordinate with **`mfa_setup_path`** / **`mfa_verification_path`** per **`SessionsController`** after-sign-in logic.
- **Tests:** **`User.skip_mfa_verification?`** + **`session`** auto-fill in **`require_mfa_if_enabled`** when **`Rails.env.test?`**.

## MFA setup and verification routes

| Route | Controller | Role |
|-------|------------|------|
| **`GET /mfa/setup`** | **`MfaSetupController#show`** | QR / secret entry |
| **`POST /mfa/verify_setup`** | **`MfaSetupController#verify`** | Confirm TOTP, set user flags |
| **`GET /mfa/verify`** | **`MfaVerificationController#show`** | Re-auth challenge (**`return_to`** via query) |
| **`POST /mfa/verify`** | **`MfaVerificationController#verify`** | Validates code, sets session keys |

**`MfaVerificationController`** uses **`before_action :require_mfa_verification`** (session user, MFA enabled, etc.) — see controller for redirect matrix.

## Discord OAuth (web)

- **`DiscordUserAuthController`** — **`skip_before_action :authenticate_user!`** and **`require_mfa_if_enabled`** for **`start`**, **`callback`**, **`verify_session`**, **`success`**; silent re-login via signed **`discord_uid`** cookie + refresh token; signup captcha (**`SignupCaptchaVerifiable`**) when enforced.
- Routes: **`GET|POST /auth/discord`**, **`GET /auth/discord/callback`**, **`GET /auth/discord/verify`**, **`GET /auth/discord/success`**, disconnect/toggle (authenticated).
- **Login speed tiers (Discord-primary):** (1) **Instant — no Discord visit:** a valid signed **`discord_uid`** cookie + a usable **`UserDiscordConnection`** (refresh token, refreshed if expired) signs the user in server-side. [`Discord::CookieSilentSignIn`](../../guildsync/app/services/discord/cookie_silent_sign_in.rb) performs the refresh and [`Discord::OAuthPrimarySession`](../../guildsync/app/services/discord/oauth_primary_session.rb) applies the Devise/Warden + MFA-gate session (shared by the controller callback and cookie paths). **`SessionsController#new`** runs this **inline on `GET /login`** (one hop straight to the dashboard; no redirect to `/auth/discord`, no `discord.com`). (2) **Silent round-trip — `prompt=none`:** returning user whose token is unusable but whose browser still has a Discord session + prior app grant (see `Discord::OAuthStartPrompt` below). (3) **Interactive:** first authorization in a browser, `prompt=none` reporting interaction required, or not logged into Discord in the browser. The Discord **desktop/mobile app** session does not count — only the **browser** session. On a dead cookie identity, `SessionsController#new` drops **`discord_uid`** but keeps **`discord_seen_before`** so a button click still gets `prompt=none`. Durable narrative: `guildsync_knowledge_base` → `implementation_reports/discord-oauth-returning-user-sign-in/`.
- **Session bounded by Discord token validity (Discord-primary only):** on protected full-page **GET HTML** requests, **`ApplicationController#require_mfa_if_enabled`** runs **`Discord::AuthSessionValidator`** for **`current_user.discord?`** users **before** the OAuth-primary MFA bypass. Valid token → continue; expired but refreshable → refreshed via **`UserDiscordConnection#refresh!`** and continue; expired **and** unrefreshable/revoked → **`enforce_discord_reauth!`** clears session/cookies and redirects to **`discord_login_path(silent: 1)`**. **Google/Microsoft** OAuth-primary and **MFA** users are **not** subject to this check; a Discord user with **no stored connection** is treated as not-applicable (no forced re-auth).
- **Silent authorize (`prompt=none`) — decided by `Discord::OAuthStartPrompt`:** [`DiscordUserAuthController#start`](../../guildsync/app/controllers/discord_user_auth_controller.rb) asks [`Discord::OAuthStartPrompt`](../../guildsync/app/services/discord/oauth_start_prompt.rb) whether to send **`prompt=none`** so **returning** users skip Discord's authorize screen. It returns **`none`** when: forced re-auth (**`?silent=1`**); a **login** where the browser shows prior app use (**`discord_seen_before`** cookie, a **`discord_uid`** cookie, or the cookie silent-login path was attempted but did not sign the user in); or a **signup** where **`discord_seen_before`** is set. It returns **`nil`** (Discord default) for **account linking** (signed-in user) and for a genuine **first-time signup** with no prior evidence. **`prompt=consent`** is never sent. When `prompt=none` is used, a one-shot **`session[:discord_oauth_prompt_none]`** is set; if Discord returns **`login_required`** / **`consent_required`** / **`interaction_required`**, the callback redirects to **`discord_login_path(interactive: 1)`** which forces a single interactive authorize (no `prompt=none`) so it cannot loop.
- **Note (web vs desktop):** silent authorize relies on the **browser's** Discord session and prior app authorization; the Discord **desktop/mobile app** session is not shared with the browser OAuth flow. **`enforce_discord_reauth!`** ([`application_controller.rb`](../../guildsync/app/controllers/application_controller.rb)) clears `discord_uid` but **keeps `discord_seen_before`** so a later manual sign-in is still treated as a returning user; only explicit **Disconnect** clears `discord_seen_before`. **Specs:** [`spec/services/discord/oauth_start_prompt_spec.rb`](../../guildsync/spec/services/discord/oauth_start_prompt_spec.rb), [`spec/requests/discord_auth_persistence_spec.rb`](../../guildsync/spec/requests/discord_auth_persistence_spec.rb), [`spec/requests/discord_user_oauth_spec.rb`](../../guildsync/spec/requests/discord_user_oauth_spec.rb).
- HTTP/interaction depth: **`overall/discord_bot.md`**; this page covers **web session + MFA gates** only.

## Gmail and Outlook OAuth (web, OIDC)

- **`GoogleUserAuthController`** / **`MicrosoftUserAuthController`** ( **`OidcUserAuthBaseController`** ) — user-facing **Gmail** and **Outlook** buttons; same **skip** pattern as Discord for **`start`**, **`callback`**, and **`verify_session`**; **gated signup** (provisional user + verified email match); **login** first by provider uid, then by a safe verified-email auto-link fallback for completed, confirmed GuildSync accounts that do not already have a provider uid. Gmail requires the provider **`email_verified`** claim. Outlook accepts Microsoft userinfo when **`email`** is present because Microsoft userinfo does not guarantee **`email_verified`**; GuildSync still requires the provider email to exactly match the verified GuildSync email before signup or auto-link. Env: **`GOOGLE_CLIENT_ID`**, **`GOOGLE_CLIENT_SECRET`**, **`MICROSOFT_CLIENT_ID`**, **`MICROSOFT_CLIENT_SECRET`**. Outlook uses the **`consumers`** authority only (personal Microsoft accounts); **organizational / Microsoft 365** tenant login is **not** this flow—register the app and authority accordingly if you add it later.
- Callback paths: **`/auth/google/callback`**, **`/auth/microsoft/callback`** (register these with each provider; host from **`default_url_options`** in production).
- Flash / errors: **`controllers.oidc_user_auth`** in locale files (including **`invalid_state`** for CSRF/state mismatch—do not reuse Discord-only keys). **Specs:** **`spec/requests/google_oauth_account_creation_spec.rb`**, **`spec/requests/microsoft_oauth_account_creation_spec.rb`**.

## Layout shells (sidebar / chrome)

**`layouts/application.html.erb`** and **`application.html+mobile.erb`**:

- **`mfa_flow_shell`** — **`controller_name` in `mfa_verification`, `mfa_setup`**.
- **`member_app_layout_chrome`** — **`user_signed_in? && mfa_verified_for_session? && !admin_sessions_shell && !mfa_flow_shell`**.

So **OAuth-primary** users with **`mfa_verified_for_session? == true`** see full chrome; **OAuth-primary users on MFA setup/verify** get the **stripped MFA shell** (no guild sidebar), matching **`spec/requests/mfa_flow_spec.rb`**.

## API v1 (brief)

**`Api::V1::BaseController`** inherits **`ApplicationController`** but **`EnsureVerifiedRealEmail`** returns early for **`api/`** paths; **`before_action :force_json_format`** runs in the child, while the email gate only applies to HTML/Turbo Stream anyway.

**`Api::V1::AuthController`** sign-up may set **`User.skip_mfa_verification_flags`** in **test** when **`skip_mfa_verification`** param is passed — keeps request specs from fighting the web MFA session layer.

## Spec pointers

| Spec | Focus |
|------|--------|
| **`spec/requests/mfa_flow_spec.rb`** | Setup/verify flows, Discord user sidebar isolation on MFA pages, redirects. |
| **`spec/requests/settings_account_auth_display_spec.rb`** | **`GET /account/settings`**: active auth-method labels (**MFA**, **Discord**, **Gmail**, **Outlook**); **OAuth-primary** users without app MFA see **`mfa_backup_warning`** (Google, Discord examples); OAuth-primary **with** MFA does not; member chrome **`support_center_url`** (default + custom, desktop + **`:mobile`**) — **changelog 294**. |
| **`spec/requests/settings_profile_spec.rb`** | **`GET /profile/settings`**: member chrome **`support_center_url`** (default + custom, desktop + **`:mobile`**) — **changelog 302**. |
| **`spec/requests/profile_settings_email_username_spec.rb`** | **`EnsureVerifiedRealEmail`** HTML redirects; profile email/username actions; **`GET /profile/email/verify`**; JSON API not gated by verified real email. |
| **`spec/requests/mfa_complete_flow_spec.rb`** | End-to-end MFA completion scenarios. |
| **`spec/requests/sessions_spec.rb`**, **`registrations_spec.rb`** | Email sign-in/up vs MFA routing. |
| **`spec/requests/discord_*`**, **`google_oauth_account_creation_spec`**, **`microsoft_oauth_account_creation_spec`** (under **`spec/requests/`**) | OAuth web paths. |

## Local development (macOS / Safari)

**`config/application.rb`** sets the session cookie **`domain`** to **`nil`** in **development** and **test**, and **`same_site: :lax`**. Using **`domain: :all`** in development produced a **`.localhost`** (or equivalent) cookie scope that **Safari rejects**, so sign-in appeared to “not stick” while other browsers worked. Use **`http://localhost:PORT`** consistently (avoid mixing **`127.0.0.1`** and **`localhost`** in the same flow, which splits cookies).

**Related:** [request_lifecycle.md](request_lifecycle.md), [app_flow_end_to_end.md](app_flow_end_to_end.md), [discord_bot.md](discord_bot.md), [site_settings_support_url.md](../systems/site_settings_support_url.md) (support link placeholders on MFA/password views).
