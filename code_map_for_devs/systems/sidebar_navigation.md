# Sidebar navigation (member app chrome)

**Last updated:** 2026-04-06 (**mega #219**, **Lane C**; **`alliance_polls_spec`** **`GET …/alliance_polls`** **`support_center_url`** — **changelog 315**; **`GET …/alliance_polls/:id`** — **changelog 316**; **`alliance_loot_rolls_spec`** **`GET …/alliance_loot_rolls`** — **changelog 317**; **`GET …/alliance_loot_rolls/:id`** — **changelog 318**; **`alliance_activity_feed_spec`** **`GET …/activity_feed`** — **changelog 319**; **`alliance_disband_votes_spec`** **`GET …/alliance_disband_votes`** — **changelog 320**; **`alliance_events_spec`** **`GET …/alliance_events`** (index) — **changelog 323**; **`GET …/alliance_events/new`** — **changelog 321**; **`GET …/alliance_events/:id`** — **changelog 322**; **`alliance_members_spec`** **`GET …/alliance_members`** **`support_center_url`** — **changelog 314**; **`alliance_messages_spec`** **`GET …/alliance_messages`** **`support_center_url`** — **changelogs 312** / **313** (**`type=gm`**, owner); **`guild_documents_spec`** **`GET …/documents/:id/edit`** **`support_center_url`** — **changelog 311**; **`GET …/documents/:id`** **`support_center_url`** — **changelog 310**; **`GET …/documents/new`** **`support_center_url`** — **changelog 309**; **`polls_spec`** **`GET …/polls/new`** + **`loot_rolls_spec`** **`GET …/loot_rolls/new`** **`support_center_url`** — **changelog 308**; **`GET …/polls/:id`** + **`GET …/loot_rolls/:id`** — **changelog 307**; **`guilds_spec`** **`GET /guilds/new`** **`support_center_url`** — **changelog 306**; **`events_bot_integration_spec`** **`GET /guilds/:id/discord_events/:id`** **`support_center_url`** — **changelog 305**; **`GET /guilds/:id/discord_events/new`** **`support_center_url`** — **changelog 304**; **`applications_spec`** **`GET /guild_applications/new`** **`support_center_url`** — **changelog 303**; **`settings_profile_spec`** **`GET /profile/settings`** **`support_center_url`** — **changelog 302**; **`roadmap_spec`** signed-in **`GET /roadmap/:id`** **`support_center_url`** — **changelog 301**; **`connections_spec`** **`GET /guilds/:id/discord/connect`** **`support_center_url`** — **changelog 300**; **`guild_member_management_spec`** **`GET /guilds/:id/members/invite`** — **changelog 299**; **`GET /guilds/:id/review_applications`** — **changelog 298**; **`GET /guilds/:id/members`** — **changelog 297**; **`guild_archives_spec`** **`GET /guild_archives`** **`support_center_url`** — **changelog 296**; **`guild_visibility_spec`** **`GET /guilds/:id/settings`** **`support_center_url`** — **changelog 295**; **`settings_account_auth_display_spec`** **`GET /account/settings`** **`support_center_url`** — **changelog 294**; **`applications_spec`** **`GET /guild_applications`** **`support_center_url`** — **changelog 293**; **`dashboard_spec`** **`GET /dashboard`** **`support_center_url`** — **changelog 292**; **`events_bot_integration_spec`** **`GET /guilds/:id/events/schedule`** **`support_center_url`** — **changelog 291**; **`loot_rolls_spec`** **`GET /guilds/:guild_id/loot_rolls`** **`support_center_url`** — **changelog 290**; **`polls_spec`** **`GET /guilds/:guild_id/polls`** **`support_center_url`** — **changelog 289**; **`gear_spec`** **`GET /guilds/:id/members_gear`** **`support_center_url`** — **changelog 288**; **`guild_documents_spec`** **`GET /guilds/:guild_id/documents`** **`support_center_url`** — **changelog 287**; **`storage_spec`** **`GET /guilds/:guild_id/storage`** **`support_center_url`** — **changelog 286**; **`guild_warnings_spec`** **`GET /guilds/:id/warnings`** + **`…/warnings/me`** **`support_center_url`** — **changelog 285**; **`message_center_isolation_spec`** **`GET /guilds/:id/message_center`** **`support_center_url`** — **changelog 284**; **`activity_feed_spec`** **`GET /guilds/:id/activity_feed`** **`support_center_url`** — **changelog 283**; **`guild_show_spec`** **`support_center_url`** on **`GET /guilds/:id`** — **changelog 277**; **`release_notes_spec`** table — **changelog 260**)

**Navigation guard:** This page covers member sidebar navigation. The admin root hub is [`admin_dashboard.md`](admin_dashboard.md).

## Where it lives

| Asset | Path under `guildsync/` |
|-------|-------------------------|
| Desktop / default partial | `app/views/shared/_sidebar.html.erb` |
| Mobile variant partial | `app/views/shared/_sidebar.html+mobile.erb` |
| Helper API | `app/helpers/application_helper.rb` — `sidebar_*` methods |
| Stimulus | `app/javascript/controllers/guild_dropdown_controller.js`, `sidebar_scroll_controller.js` (names match `data-controller` on sidebar markup) |

Root element **`id="sidebar"`** — request specs assert presence/absence (e.g. MFA/admin shells omit member chrome).

## Structure (conceptual)

1. **Universal menu** — collapsible (`guild-dropdown`); Discord connection card; global links (dashboard, roadmap, my applications, member guild list, apply, optional create guild / archived guilds / alliances hub).
2. **Guilds I own** — per-guild dropdowns with dashboard, alliance affordances (invites, join requests), then **plan- and permission-gated** guild links (see below).
3. **Guilds I’m in** (non-owner) — similar nested links with member-appropriate gates.

## Plan entitlements (`plan_allows?`)

Guild submenu entries consult **`plan_allows?`** for the **current user’s** plan (same idea as `plan_entitlements.yml` / `PlanEntitlementService`). Typical keys used in the sidebar:

| Key | Meaning in UI |
|-----|----------------|
| `:alliance_hub` | Owner-only alliance creation/join affordances when not already in an alliance |
| `:message_center` | Link to guild message center |
| `:guild_documents` | Documents (also requires `can_manage_documents?(guild)`) |
| `:ai_gear_scanner` | **AI Gear Scanner** / members gear (`sidebar.guild_menu.members_gear` i18n) |
| `:activity_feed` | Activity feed (also `can_view_activity_feed?(guild)`) |
| `:warnings` | Warnings management (also `can_manage_warnings?(guild)`) |

**Top-level alliances link:** `show_alliances_top_nav?(user)` — true if the user is tied to an **active** alliance **or** `user.plan_allows?(:alliance_hub)`.

**Create guild:** `show_nav_create_guild?(user)` → `user.can_create_guild?` (mirrors `GuildsController` limits).

**Archived guilds:** `show_nav_archived_guilds?(user)` — only if `user.owned_guilds.exists?`.

## Universal “My warnings” link

`sidebar_target_guild_for_my_warnings` picks a **persisted** guild for `guild_my_warnings_path(guild)` by checking, in order: controller `@guild`, `params[:guild_id]`, then owned active guilds, then member guilds — each gated by `can_access_my_warnings_page_for_guild?` (owner or active member).

## Mobile

`mobile_variant_spec.rb` covers **`mobile-sidebar-panel`** visibility vs desktop layout. Toast band inset vs full-width when sidebar hidden: `flash_toast_layout_spec.rb`.

## Spec pointers

| Spec | What it covers |
|------|----------------|
| `spec/requests/dashboard_spec.rb` | Universal menu, Discord sidebar copy, “My warnings”, archived guilds visibility; **`GET /dashboard`** **`support_center_url`** (**changelog 292**) |
| `spec/requests/guilds_spec.rb` | **`GET /guilds`** (**my guilds**) **`support_center_url`** (**280**); **`GET /guilds/new`** (**306**) |
| `spec/requests/guild_show_spec.rb` | Quick actions vs sidebar destinations; **`support_center_url`** in signed-in guild chrome (**changelog 277**) |
| `spec/requests/activity_feed_spec.rb` | Sidebar member guild menu; **`GET /guilds/:id/activity_feed`** **`support_center_url`** (**changelog 283**) |
| `spec/requests/alliance_messages_spec.rb` | Alliance chat (**`all_members`** **312**; **`type=gm`** owner **313**); **`GET …/alliance_messages`** **`support_center_url`** |
| `spec/requests/alliance_members_spec.rb` | **`GET …/alliance_members`** member directory **`support_center_url`** (**changelog 314**) |
| `spec/requests/alliance_polls_spec.rb` | **`GET …/alliance_polls`** polls index **`support_center_url`** (**changelog 315**); **`GET …/alliance_polls/:id`** (**changelog 316**) |
| `spec/requests/alliance_loot_rolls_spec.rb` | **`GET …/alliance_loot_rolls`** **`support_center_url`** (**changelog 317**); **`GET …/alliance_loot_rolls/:id`** (**changelog 318**) |
| `spec/requests/alliance_activity_feed_spec.rb` | **`GET …/activity_feed`** **`support_center_url`** (**changelog 319**) |
| `spec/requests/alliance_disband_votes_spec.rb` | **`GET …/alliance_disband_votes`** **`support_center_url`** (**changelog 320**) |
| `spec/requests/alliance_events_spec.rb` | **`GET …/alliance_events`** index **`support_center_url`** (**changelog 321**); **`GET …/alliance_events/new`** (**changelog 321**); **`GET …/alliance_events/:id`** (**changelog 322**) |
| `spec/requests/message_center_isolation_spec.rb` | **`GET /guilds/:id/message_center`** **`support_center_url`** (**changelog 284**) |
| `spec/requests/guild_warnings_spec.rb` | **`GET /guilds/:id/warnings`** + **`GET /guilds/:id/warnings/me`** **`support_center_url`** (**changelog 285**) |
| `spec/requests/storage_spec.rb` | Folders in sidebar; **`GET /guilds/:guild_id/storage`** **`support_center_url`** (**changelog 286**) |
| `spec/requests/guild_documents_spec.rb` | **`GET /guilds/:guild_id/documents`** (**287**); **`GET …/documents/new`** (**309**); **`GET …/documents/:id`** (**310**); **`GET …/documents/:id/edit`** (**311**) **`support_center_url`** |
| `spec/requests/gear_spec.rb` | **`GET /guilds/:id/members_gear`** **`support_center_url`** (**changelog 288**) |
| `spec/requests/polls_spec.rb` | **`GET /guilds/:guild_id/polls`** (**289**); **`GET …/polls/new`** (**308**); **`GET …/polls/:id`** (**307**) |
| `spec/requests/loot_rolls_spec.rb` | **`GET /guilds/:guild_id/loot_rolls`** (**290**); **`GET …/loot_rolls/new`** (**308**); **`GET …/loot_rolls/:id`** (**307**) |
| `spec/requests/events_bot_integration_spec.rb` | **`GET /guilds/:id/events/schedule`** **`support_center_url`** (**changelog 291**); **`GET /guilds/:id/discord_events/new`** (**304**); **`GET /guilds/:id/discord_events/:id`** (**305**) |
| `spec/requests/applications_spec.rb` | **`GET /guild_applications`** **`support_center_url`** (**293**); **`GET /guild_applications/new`** (**303**) |
| `spec/requests/settings_account_auth_display_spec.rb` | **`GET /account/settings`** **`support_center_url`** (**changelog 294**) |
| `spec/requests/settings_profile_spec.rb` | **`GET /profile/settings`** **`support_center_url`** (**changelog 302**) |
| `spec/requests/guild_visibility_spec.rb` | **`GET /guilds/:id/settings`** **`support_center_url`** (**changelog 295**); **`GET /member/dashboard`** (**279**) |
| `spec/requests/guild_archives_spec.rb` | **`GET /guild_archives`** **`support_center_url`** (**changelog 296**) |
| `spec/requests/guild_member_management_spec.rb` | **`GET /guilds/:id/members`** **`support_center_url`** (**297**); **`GET /guilds/:id/review_applications`** (**298**); **`GET /guilds/:id/members/invite`** (**299**) |
| `spec/requests/discord/connections_spec.rb` | **`GET /guilds/:id/discord/connect`** **`support_center_url`** (**300**) |
| `spec/requests/roadmap_spec.rb` | Signed-in **`GET /roadmap`** release link **`support_center_url`** (**276**); **`GET /roadmap/:id`** member chrome (**301**) |
| `spec/requests/mobile_variant_spec.rb` | Mobile drawer / panel |
| `spec/requests/mfa_flow_spec.rb`, `spec/requests/admin/sessions_spec.rb` | No `id="sidebar"` on isolated shells |
| `spec/helpers/application_helper_spec.rb` | `sidebar_discord_username_line` |
| `spec/requests/release_notes_spec.rb` | Dashboard includes support URL; guest **`GET /roadmap`** title/footer (**changelog 260**); per-guild home **`support_center_url`** — **`guild_show_spec`** (**changelog 277**) |

**Related maps:** [plan_entitlements.md](plan_entitlements.md), [guilds_crud.md](guilds_crud.md), [guild_polls_loot_rolls.md](guild_polls_loot_rolls.md) (**mega #210** — polls / loot routes, Cable, Stimulus), [alliances.md](alliances.md), [overall/app_flow_end_to_end.md](../overall/app_flow_end_to_end.md).
