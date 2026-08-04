# Support links (site settings)

**Last updated:** 2026-05-27 (`release_notes_url` is the permanent admin-managed support-pages URL; MFA and account recovery Contact Support now use it through the public support redirect; homepage footer links remain separate)

GuildSync has **two support-link patterns**:

- Support-page flows resolve through the **`release_notes_url`** key. This includes signed-in shell help links, `/release-notes`, signed-in `/support/contact`, MFA verification, and account recovery.
- The homepage footer support links use **three separate DB-backed URLs** so marketing admins can manage Documentation, Contact, and Discord independently without code changes.

## Data layer

| Piece | Location / behavior |
|-------|---------------------|
| **Support-pages key** | **`release_notes_url`** in **`site_settings`** rows (`SiteSetting` model). The admin UI labels this “URL For Support Pages”; the key name remains unchanged for compatibility. |
| **Footer keys** | **`homepage_footer_documentation_url`**, **`homepage_footer_contact_url`**, **`homepage_footer_discord_url`** in **`site_settings`** rows. |
| **Defaults** | Support pages and footer documentation/contact default to `https://guildsync.raiseaticket.com`; Discord defaults to `ENV["COMMUNITY_DISCORD_INVITE_URL"]` or the widget URL fallback in `SiteSetting::DEFAULTS`. |
| **Readers** | **`SiteSetting.release_notes_url`**, **`homepage_footer_documentation_url`**, **`homepage_footer_contact_url`**, **`homepage_footer_discord_url`**. |
| **Writers** | **`SiteSetting.set(key, url)`** — **`find_or_initialize_by`**, **`save!`**. Defaults are read-only fallbacks; rendering admin pages, booting the app, running migrations, or deploying code must not overwrite an existing production row. |

Admin writes validate URLs with **`Guildsync::ExternalRedirectUrl`** before persisting them, so saved support and footer links must be non-blank HTTP(S) URLs with a host and no redirect-header splitting characters. The model still keeps storage simple and does not validate URL shape directly.

## Routes

| Method / path | Controller#action | Notes |
|---------------|-------------------|--------|
| **`GET /release-notes`** | **`SettingsController#release_notes`** | **`public_page?`** exempt from auth; **302** to **`SiteSetting.release_notes_url`** (**`allow_other_host: true`**). Used by public support-page buttons such as MFA verification and account recovery. |
| **`GET /support/contact`** | **`SupportController#contact`** | Auth required; preserves session keys then **redirect** to same URL (see **`authentication_persistence_spec`**). |
| **`GET /support/documentation`** | **`FooterSupportLinksController#documentation`** | Public homepage-footer redirect to **`SiteSetting.homepage_footer_documentation_url`**. |
| **`GET /support/contact-link`** | **`FooterSupportLinksController#contact`** | Public homepage-footer redirect to **`SiteSetting.homepage_footer_contact_url`**. |
| **`GET /support/discord`** | **`FooterSupportLinksController#discord`** | Public homepage-footer redirect to **`SiteSetting.homepage_footer_discord_url`**. |
| **`GET /admin/settings/release-notes`** | **`Admin::SiteSettingsController#release_notes`** | “URL For Support Pages” admin UI; title + back link outside **`turbo-frame`** **`admin_release_notes_main`**; frame holds **`_release_notes_main`** (flash + form + where-used list). **`Turbo-Frame: admin_release_notes_main`** → **`release_notes_frame`** (**`layout: false`**) — **mega #223**. |
| **`PATCH /admin/settings/release-notes`** | **`Admin::SiteSettingsController#update_release_notes`** | Param **`release_notes_url`**; Turbo success → **`release_notes_refresh.turbo_stream.erb`**; invalid URL + Turbo → **303** + flash (**mega #175**). |
| **`GET /admin/homepage-footer`** | **`Admin::HomepageFooterSettingsController#show`** | Full-page admin editor for homepage footer support links + legal-page entry points. |
| **`PATCH /admin/homepage-footer`** | **`Admin::HomepageFooterSettingsController#update`** | Validates three HTTPS URLs, persists to `site_settings`, and writes audit action **`update_homepage_footer_support_links`**. |

Named routes include **`release_notes_path`**, **`contact_support_path`**, **`footer_support_documentation_path`**, **`footer_support_contact_path`**, **`footer_support_discord_path`**, **`admin_release_notes_settings_path`**, **`update_release_notes_settings_path`**, **`admin_homepage_footer_settings_path`**.

## App-wide helper

**`ApplicationController#support_center_url`** returns **`SiteSetting.release_notes_url`** and is exposed as **`helper_method :support_center_url`**. Most sidebar, top bar, layout, roadmap, pricing, billing, and app “support / contact / docs” links use this helper and open in a **new tab** (**`target: "_blank"`**, **`rel: "noopener"`** / **`noreferrer`**).

**`SearchController`** registers **`contact_support_path`** as an in-app search target (“Contact Support”) — that path redirects through **`SupportController`** (session-aware) rather than linking the raw external URL.

The homepage footer intentionally does **not** use `support_center_url` for its three support items. It points at internal redirect routes so admins can tune each destination separately in the DB.

## Public support-page buttons

- **`passwords/new`** — account recovery “Contact Support” links to **`release_notes_path`**, which redirects to **`SiteSetting.release_notes_url`**.
- **`mfa_verification/show`** — “Contact Support” links to **`release_notes_path`**, which works before MFA is complete and still uses the support-pages URL.
- **`settings/release_notes.html.erb`** — separate page that may render sanitized HTML or fallback links; still references **`SiteSetting.release_notes_url`** for “Zoho Support” style links when the inline HTML path is empty.

## Admin UI copy

Dashboard quick actions include both **“URL For Support Pages”** and the homepage **“Footer Links & Legal Pages”** editor. Support-pages saves log **`AdminAuditLog`** action **`update_release_notes_url`**; footer-link saves log **`update_homepage_footer_support_links`**.

## Specs

| Spec | Focus |
|------|--------|
| **`spec/models/site_setting_spec.rb`** | **`get`/`set`**, **`release_notes_url`**, defaults. |
| **`spec/requests/homepage_footer_links_spec.rb`** | Homepage footer support-link hrefs, redirects, and legal-page entry points. |
| **`spec/requests/admin/homepage_footer_settings_spec.rb`** | Admin footer-link URL edits, validation including malformed HTTP URLs, audit logging, and legal-page edit flow. |
| **`spec/requests/release_notes_spec.rb`** | **`GET /release-notes`** redirect (desktop + **`:mobile`** — **changelog 269**); **`GET /support/contact`** when signed in (desktop + **`:mobile`** — **changelog 270**); **guest** **`GET /support/contact`** — redirect **`Location`** omits default + custom support hosts (**changelogs 271–272**); dashboard / sidebar include configured URL; avatar dropdown **`layouts.application.dropdown.release_notes`** + **`ERB::Util.html_escape`** on **`release_notes_instructions`** (**changelog 262**); mobile User-Agent **`GET /dashboard`** — same dropdown (**changelog 263**); mobile **`GET /dashboard`** — default + custom **`release_notes_url`** in HTML (**changelog 267**); guest **`GET /roadmap`** asserts escaped **`roadmap.title`** in HTML and **`roadmap.guest_footer_note`**; guest **`GET /roadmap`** **`:mobile`** — same (**changelog 266**); release link card remains signed-in-only — **`roadmap_spec`** + **`feature_requests_roadmap.md`**; signed-in roadmap **`support_center_url`** in HTML — **`roadmap_spec`** **changelog 276**. |
| **`spec/requests/admin/site_settings_spec.rb`** | Admin **GET/PATCH**, “URL For Support Pages” copy, configured-row permanence on render, Turbo streams, audit log, invalid/malformed URL rejection. |
| **`spec/requests/password_new_spec.rb`** | Account recovery “Contact Support” uses **`release_notes_path`**, not homepage footer contact, and resolves through the current support-pages URL. |
| **`spec/requests/login_with_both_methods_spec.rb`** | MFA verification “Contact Support” uses **`release_notes_path`**, not **`#`**, and resolves through the current support-pages URL. |
| **`spec/requests/authentication_persistence_spec.rb`** | **`GET contact_support_path`** session behavior. |
| **`spec/requests/home_landing_spec.rb`** | Guest **`GET /`** — footer documentation/contact/Discord links use dedicated footer support redirect routes backed by **`homepage_footer_*`** settings (desktop + **`:mobile`**). |
| **`spec/requests/pricing_spec.rb`** | Signed-in **`GET /pricing/upgrade`** — **`support_center_url`** in contact copy (default + custom, desktop + **`:mobile`** — **changelog 274**). |
| **`spec/requests/billing_spec.rb`** | **`GET /billing`** (**active subscription**) — **`support_center_url`** in billing contact link (default + custom, desktop + **`:mobile`** — **changelog 275**). |
| **`spec/requests/roadmap_spec.rb`** | Signed-in **`GET /roadmap`** — **`support_center_url`** on **`roadmap.release_notes_link`** (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 276**). Signed-in **`GET /roadmap/:id`** — member chrome **`support_center_url`** (same matrix — **changelog 301**). |
| **`spec/requests/guild_show_spec.rb`** | **`GET /guilds/:id`** — **`support_center_url`** in signed-in guild chrome (default + custom, desktop + **`:mobile`** — **changelog 277**). |
| **`spec/requests/alliances_spec.rb`** | **`GET /alliances`** (hub, alliance member) — **`support_center_url`** in member chrome (default + custom, desktop + **`:mobile`** — **changelog 278**). **`GET /alliances/:id`** (show, alliance member) — same (**changelog 282**). |
| **`spec/requests/alliance_messages_spec.rb`** | **`GET …/alliance_messages`** (**`all_members`**, alliance member) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 312**). **`GET …`** (**`type=gm`**, guild owner) — same matrix — **changelog 313**. |
| **`spec/requests/alliance_members_spec.rb`** | **`GET …/alliance_members`** (alliance member) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 314**). |
| **`spec/requests/alliance_polls_spec.rb`** | **`GET …/alliance_polls`** (alliance member) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 315**). **`GET …/alliance_polls/:id`** — same matrix — **changelog 316**. |
| **`spec/requests/alliance_loot_rolls_spec.rb`** | **`GET …/alliance_loot_rolls`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 317**). **`GET …/alliance_loot_rolls/:id`** — same matrix — **changelog 318**. |
| **`spec/requests/alliance_activity_feed_spec.rb`** | **`GET …/activity_feed`** (alliance guild owner) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 319**). |
| **`spec/requests/alliance_disband_votes_spec.rb`** | **`GET …/alliance_disband_votes`** (alliance GM) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 320**). |
| **`spec/requests/alliance_events_spec.rb`** | **`GET …/alliance_events`** (index, alliance member) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 323**). **`GET …/alliance_events/new`** (alliance guild owner) — same matrix — **changelog 321**. **`GET …/alliance_events/:id`** (**`#show`**) — same matrix — **changelog 322**. |
| **`spec/requests/guild_visibility_spec.rb`** | **`GET /member/dashboard`** (apply-to-guild / discoverability shell) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 279**). **`GET /guilds/:id/settings`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 295**). |
| **`spec/requests/guilds_spec.rb`** | **`GET /guilds`** (**my guilds** list) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 280**). **`GET /guilds/new`** (**create guild** form) — same matrix — **changelog 306**. |
| **`spec/requests/leaderboard_spec.rb`** | **`GET /leaderboard`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 281**). |
| **`spec/requests/activity_feed_spec.rb`** | **`GET /guilds/:id/activity_feed`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 283**). |
| **`spec/requests/message_center_isolation_spec.rb`** | **`GET /guilds/:id/message_center`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 284**). |
| **`spec/requests/guild_warnings_spec.rb`** | **`GET /guilds/:id/warnings`** (managers) and **`GET /guilds/:id/warnings/me`** (members) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 285**). |
| **`spec/requests/storage_spec.rb`** | **`GET /guilds/:guild_id/storage`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 286**). |
| **`spec/requests/guild_documents_spec.rb`** | **`GET /guilds/:guild_id/documents`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 287**). **`GET …/documents/new`** — same matrix — **changelog 309**. **`GET …/documents/:id`** — same matrix — **changelog 310**. **`GET …/documents/:id/edit`** — same matrix — **changelog 311**. |
| **`spec/requests/gear_spec.rb`** | **`GET /guilds/:id/members_gear`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 288**). |
| **`spec/requests/polls_spec.rb`** | **`GET /guilds/:guild_id/polls`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 289**). **`GET …/polls/new`** — same matrix — **changelog 308**. **`GET …/polls/:id`** — same matrix — **changelog 307**. |
| **`spec/requests/loot_rolls_spec.rb`** | **`GET /guilds/:guild_id/loot_rolls`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 290**). **`GET …/loot_rolls/new`** — same matrix — **changelog 308**. **`GET …/loot_rolls/:id`** — same matrix — **changelog 307**. |
| **`spec/requests/events_bot_integration_spec.rb`** | **`GET /guilds/:id/events/schedule`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 291**). **`GET /guilds/:id/discord_events/new`** (`DiscordEventsController#new`, **`new_guild_discord_event_path`**) — same matrix — **changelog 304**. **`GET /guilds/:id/discord_events/:id`** (`DiscordEventsController#show`, **`guild_discord_event_path`**) — same matrix — **changelog 305**. |
| **`spec/requests/dashboard_spec.rb`** | **`GET /dashboard`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 292**; complements **`release_notes_spec`** **262–263**, **267**). |
| **`spec/requests/applications_spec.rb`** | **`GET /guild_applications`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 293**). **`GET /guild_applications/new`** — same (**changelog 303**). |
| **`spec/requests/settings_account_auth_display_spec.rb`** | **`GET /account/settings`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 294**). |
| **`spec/requests/settings_profile_spec.rb`** | **`GET /profile/settings`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 302**). |
| **`spec/requests/guild_archives_spec.rb`** | **`GET /guild_archives`** (archived guilds index) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 296**). |
| **`spec/requests/guild_member_management_spec.rb`** | **`GET /guilds/:id/members`** (members list) — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 297**). **`GET /guilds/:id/review_applications`** — same (**changelog 298**). **`GET /guilds/:id/members/invite`** — same (**changelog 299**). |
| **`spec/requests/discord/connections_spec.rb`** | **`GET /guilds/:id/discord/connect`** — **`support_center_url`** (default + custom, desktop + **`:mobile`** — **changelog 300**). |

## Related maps

- **`systems/admin_dashboard.md`** — quick action to support settings.
- **`overall/request_specs_and_gates.md`** — **`site_settings_spec`** row (**mega #175** / **#191** / **#223** GET frame).
- **`systems/content_moderation.md`** / **`feature_requests_roadmap.md`** — product moderation vs this external support URL.
