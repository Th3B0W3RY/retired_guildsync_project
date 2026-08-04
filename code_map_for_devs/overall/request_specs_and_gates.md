# Request specs as enforcement documentation

**Last updated:** 2026-04-11 (homepage footer support-link redirects + legal-page CMS specs added; prior mega sweep remains intact)

This page lists **high-signal** request/service specs that encode product rules (plan tier, guild permissions, isolation). Use it when changing gates or adding routes—update the relevant spec and this table in the same PR.

## Homepage footer support + legal pages

| Spec | What it proves |
|------|----------------|
| `spec/requests/homepage_footer_links_spec.rb` | Guest `GET /` footer renders product links plus dedicated support/legal paths; documentation/contact/Discord routes redirect to the configured DB URLs; `/privacy`, `/terms`, and `/security` render standalone pages. |
| `spec/requests/admin/homepage_footer_settings_spec.rb` | Admin `GET /admin/homepage-footer` renders the footer/legal editor; `PATCH /admin/homepage-footer` validates and persists the three support URLs in `site_settings`; `PATCH /admin/marketing-legal-pages/:id` updates legal-page title/body and writes audit logs. |

## Member dashboard (signed-in home)

| Spec | What it proves |
|------|----------------|
| `spec/requests/dashboard_spec.rb` | **`GET /dashboard`**: global quick actions use **`dashboard.view_guilds`**, **`my_applications`**, **`apply_to_guild`**, **`archived_guilds`**, **`alliances`** via **`I18n`** (desktop + mobile templates have no inline **`default:`** for those keys). Signed-in **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 292**, **Lane C** (complements **`release_notes_spec`** dashboard dropdown / mobile shell — **changelogs 262–263**, **267**). |

## Account settings (signed-in)

| Spec | What it proves |
|------|----------------|
| `spec/requests/settings_account_auth_display_spec.rb` | **`GET /account/settings`** (`SettingsController#account`): active auth-method labels; **OAuth-primary without MFA** shows backup (**`mfa_backup_warning`**); **OAuth-primary with MFA** does not; signed-in **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 294**, **Lane C**. Cross-map: **`overall/authentication_mfa.md`** (**mega #194**). |
| `spec/requests/settings_profile_spec.rb` | **`GET /profile/settings`** (`SettingsController#profile`): member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 302**, **Lane C**. Cross-map: **`overall/authentication_mfa.md`**. |

## Cross-guild member leaderboard

| Spec | What it proves |
|------|----------------|
| `spec/requests/leaderboard_spec.rb` | **`GET /leaderboard`**: **`authenticate_user!`** (examples use **`sign_in`**); no **`on_time`** or only **`scheduled`** events → empty-state copy; **`in_progress`** / **`completed`** on-time participations weighted **×10**; sort by score; server label from **`GuildDiscordSetting#discord_guild_name`** or guild **name** fallback; multiple guild memberships aggregated; **no** data from guilds the user is not in; member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 281**, **Lane C**. **Map:** **`systems/member_leaderboard.md`** (**mega #198**). |
| `spec/services/guilds/member_leaderboard_scores_spec.rb` | **`Guilds::MemberLeaderboardScores`** scoring and grouping (poll votes, loot **`closed`**, etc.). |

## MFA and session gates

| Spec | What it proves |
|------|----------------|
| `spec/requests/mfa_flow_spec.rb` | MFA setup/verify HTTP flows; **Discord** users on **`mfa_setup`**/**`mfa_verification`** do **not** get member app sidebar (**`mfa_flow_shell`**). Cross-map: **`overall/authentication_mfa.md`** (**mega #194**). |
| `spec/requests/mfa_complete_flow_spec.rb` | End-to-end MFA completion (happy paths + edge redirects). Cross-map: **`overall/authentication_mfa.md`** (**mega #194**). |

## Subscription cancellation (service, Stripe stubs)

| Spec | What it proves |
|------|----------------|
| `spec/services/subscription_cancellation_service_spec.rb` | **`SubscriptionCancellationService.call`**: missing sub; **local** `cancel!` without Stripe id; Stripe **cancel** when no `first_paid_invoice_at`; **`cancel_at_period_end`** when paid and outside refund window; **refund + cancel** inside policy window (invoice list stubbed); **StripeError** → failure. **`resume!`**: no Stripe id → error; else **`cancel_at_period_end: false`**. |
| `spec/requests/billing_spec.rb` | **`GET /billing`** with **`session_id`** (checkout success): **`flash[:notice]`** = **`controllers.billing.checkout_success`** (**mega #121**). **`POST /billing/cancel_subscription`** and **`resume_subscription`**: no **`stripe_subscription_id`** → **`controllers.billing.no_stripe_subscription`** (HTML flash / JSON 422); with Stripe id → **`SubscriptionCancellationService`** success (**`canceled_at_period_end`**, **`subscription_resumed`**) HTML + JSON. **`POST /billing/change_plan`**: invalid or **inactive** **`plan_id`** → **422** JSON + **`error`**, or **HTML** → **`billing_path`** + **`flash[:alert]`** (**`controllers.billing.plan_not_found`**). **`GET /billing/preview_plan_change`**: invalid/inactive → **404** JSON + **`error`**, or **HTML** → **`billing_path`** + **`flash[:alert]`** (**`controllers.billing.plan_not_found`**). **`POST /billing/create_checkout_session` (JSON)**: **`I18n.t`** for **`checkout_price_id_required`**, **`checkout_active_subscription_use_portal`**, **`checkout_payment_setup_failed`**, **`checkout_failed`**. **`POST /billing/portal` (JSON)**: **`url`** success; Stripe failures → **`portal_session_create_failed`** / **`portal_customer_init_failed`** (**mega #120**). **`GET /billing`** (**`BillingController#show`**, active subscription) — **`support_center_url`** in contact link (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 275**, **Lane C**. |
| `spec/services/admin/guild_ownership_transfer_service_spec.rb` | Handover + billing: **`:period_end`** when previous owner has **`stripe_subscription_id`** + **`first_paid_invoice_at`** (Stripe **`update`** stubbed). |

## Plan tier matrix (`plan_entitlements.yml`)

| Spec | What it proves |
|------|----------------|
| `spec/requests/plan_entitlements_matrix_spec.rb` | Free vs Basic vs Upgraded vs **Elite** for activity feed, message center, warnings, documents, storage, **members gear** (`:ai_gear_scanner`). Expect `upgrade_pricing_path` + `plan_entitlements.upgrade_required` when denied. **Elite** matches **Upgraded** on all listed **GET**s (**200**). |
| `spec/services/plan_entitlement_service_spec.rb` | `PlanEntitlementService.allowed?` vs YAML rows; `beta_features` flag vs Elite row; unknown plan name → no implicit features. |

## API v1 — guilds and guild members

**Cross-cutting:** **`Api::V1::BaseController`** JSON errors use **`api.v1.*`** (**mega #112**). **`Api::V1::AuthController`** uses **`api.auth.*`** (**mega #113**). **`Api::V1::DiscordController`** uses **`api.discord.*`** (**mega #114**).

| Spec | What it proves |
|------|----------------|
| `spec/requests/api/v1/auth_spec.rb` | Sign-up / sign-in / **`GET …/auth/me`**; unauthenticated **`me`** → **`api.v1.authentication_required`**; invalid password → **`api.auth.invalid_sign_in`** (**mega #113**). |
| `spec/requests/api/v1/guilds_spec.rb` | **`GET /api/v1/guilds/:id`**: **`Api::V1::GuildsController#set_guild`** resolves via membership / ownership / **`owner_id`**; **`show`** also allows **`publicly_listed`** guilds (**200** for non-member). Private guilds the user cannot access → **404** JSON **`controllers.guilds.access_denied`** (not **403**). **`PATCH`** / **`DELETE`** use the same resolution without the public branch. |
| `spec/requests/api/v1/guild_members_spec.rb` | **`GET …/members`**: stranger to **`guild_id`** → **404** + **`access_denied`**. **`authorize_guild_access`** denial → **404** + **`access_denied`** (defensive example stubs **`guild_members.exists?`**; **mega #111**). **`PATCH`** / **`DELETE …/members/:id`**: unknown **`id`** or **`GuildMember`** from another guild → **404** + **`access_denied`** (**mega #110**). |
| `spec/requests/api/v1/discord_spec.rb` | **`GET/PATCH …/discord/channels`**, **`POST …/discord/events/:id/signup`**: no guild access → **404** + **`access_denied`**; **`manage_discord?`** deny → **403** + **`api.v1.not_authorized`**; Discord not connected → **422** + **`api.discord.not_connected`**; signup missing identity → **422** + **`api.discord.missing_discord_identity`**; unknown **`event_id`** in guild → **404** + **`api.discord.event_not_found`**; inactive member signup → **403** + **`api.v1.not_authorized`** (**mega #114**). |
| `spec/requests/api/v1/events_spec.rb` | **`GET/PATCH/DELETE …/api/v1/events/:id`**, **`participate`**, **`participants`**: **`set_event`** requires **`EventPolicy#show?`** (owner or **active** member); outsider, unknown id, or **inactive** member → **404** + **`access_denied`** (no **`Event.find`** probe). **`PATCH`** still returns **403** when the user may **show** but not **`update?`**. Nested **`GET/POST …/guilds/:guild_id/events`** unchanged (**`set_guild_for_guild_events`**). |
| `spec/requests/api/v1/users_spec.rb` | **`GET/PATCH/POST archive …/api/v1/users/:id`**: **`set_user`** uses **`find_by`** + per-action **`UserPolicy`** (**`show?`**, **`update?`**, **`guilds?`**, **`archive?`**); unknown id or disallowed target → **404** + **`controllers.guilds.access_denied`** (replaces **`User.find`** **404** “Resource not found” / **403** Pundit for cross-user reads). **`UserPolicy#archive?`** aliases **`update?`**; **`archive`** calls **`authorize @user, :archive?`**. Self-archive **200** + **`api.users.account_archived`** **`message`**. |

## Guild show (per-guild home)

| Spec | What it proves |
|------|----------------|
| `spec/requests/guild_show_spec.rb` | **`GET /guilds/:id`**: quick actions vs sidebar; Discord invite; profile **`PATCH`**; signed-in member chrome includes **`support_center_url`** (sidebar / layout; default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 277**, **Lane C**. **Map:** **`systems/guilds_crud.md`**, **`systems/sidebar_navigation.md`**, **`systems/site_settings_support_url.md`**. |

## Guild applications (public discoverability)

| Spec | What it proves |
|------|----------------|
| `spec/requests/applications_spec.rb` | **`GET /guild_applications`**: signed-in index — member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 293**, **Lane C**. **`GET /guild_applications/new`**: same **`support_center_url`** matrix — **changelog 303**, **Lane C**. **`POST /guild_applications`**: private (**`publicly_listed: false`**) or **archived** guild id → no new row; **`flash[:alert]`** = **`guild_applications.create.guild_not_available`**. **`PATCH …/accept`**: bogus id or application for another guild → **`my_guilds_path`** + **`controllers.guilds.access_denied`**; no **`Guild.find`** / **`RecordNotFound`**. |
| `spec/requests/guild_member_management_spec.rb` | **`Application Management Permissions`**: user without **`can_manage_applications?`** cannot **`PATCH …/accept`** (**`my_guilds_path`** + **`access_denied`**). |
| `spec/requests/guild_visibility_spec.rb` | **`GET /member/dashboard`**: **`@available_guilds`** excludes **archived** listed guilds (**`Guild.discoverable_for_applications`**); member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 279**, **Lane C**. **`GET /guilds/:id/settings`** (owner): member chrome includes **`support_center_url`** (default + custom, desktop + **`:mobile`**) — **changelog 295**, **Lane C**. **`GET /guilds/search`**: same scope — **archived** public guilds omitted from JSON results. |

## Guild invites — applicant accept/deny + officer dismiss

| Spec | What it proves |
|------|----------------|
| `spec/requests/guild_invites_spec.rb` | **`PATCH …/accept`** / **`deny`**: signed-in user who is **not** the invitee → **`my_guilds_path`** + **`controllers.guilds.access_denied`** (invite loaded only via **`current_user.guild_invites`**). **`PATCH …/dismiss`**: **guild owner** can set **`dismissed`** and redirect to **`guild_review_applications_path`**; **stranger** → **`access_denied`**, invite unchanged. **`POST …/invite_user`**, user search, Discord stubs unchanged. |

## AI Gear — members gear page + API

| Spec | What it proves |
|------|----------------|
| `spec/requests/gear_spec.rb` | **`POST /guilds/:id/gear/upload`**, **`GET …/gear/:user_id`**, **`POST …/gear/request`**, **`POST …/gear/request_bulk`**, permissions; non-members get **404** JSON **`controllers.guilds.access_denied`** when **`guild_id`** is not theirs (same resolution as **`GuildsController#set_guild`**). **`GET …/gear/:user_id`** and **`POST …/gear/request`**: target resolved with **`@guild.members.find_by(id: user_id)`** — non-member or unknown id → **404** + **`access_denied`** (replaces **`User.find`** / distinct **403**/**422** copy). Upload validation / OCR failure → **`gear.api.*`** (**`I18n.t`** in spec); **`POST …/gear/request`** success + duplicate pending **`message`** → **`gear.api.request_created`** / **`request_already_pending`** (**`%{name}`**); regular member denied gear request → **403** **`api.v1.not_authorized`**. **`GET /guilds/:id/members_gear`**: banner includes **`guilds.members_gear.pending_request_officer_banner`** when a **`GearUploadRequest`** is **pending** for **`current_user`**, absent otherwise (**Upgraded** plan + Discord **`auth_method`** on member); member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 288**, **Lane C**. Banner string: **`guilds.members_gear`** in **`config/locales/{locale}/{locale}.yml`**. **Map:** **`systems/ocr_ai_gear.md`** (**mega #203**). |
| `spec/models/gear_upload_request_spec.rb` | **`GearUploadRequest#requester_can_request`**: owner / admin / moderator; member vs **`guild.permission_role_*`** + **`role_*_can_manage_gear_requests`**; inactive **`GuildMember`**; **`pending_for_user`**, **`#mark_completed!`**. |

## Free plan downgrade (alliances)

| Spec | What it proves |
|------|----------------|
| `spec/services/free_plan_downgrade_side_effects_spec.rb` | `FreePlanDowngradeSideEffects.call` strips owned guilds from alliances (`AllianceGuild` → left), leader succession to next active guild by `created_at`, `AllianceMember` rows for that guild → removed, `alliance_downgrade_snapshot` on user; non-leader member guild; no-op paths. |

## Alliance — hub, show, plan gate

| Spec | What it proves |
|------|----------------|
| `spec/requests/alliances_spec.rb` | **`GET /alliances`**: paid member sees hub; paid non-member blank hub; **Free** without **`AllianceMember`** → **`dashboard_path`** + **`alliances.errors.plan_required_for_alliance_hub`**; hub HTML includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 278**, **Lane C**. **`GET /alliances/:id`**: member **200**; paid non-member or unknown **`id`** → **`dashboard_path`** + **`controllers.guilds.access_denied`**; **Free** non-member → same **plan** redirect as hub (before **`require_alliance_member`**); member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 282**, **Lane C**. |

## Alliance — guild owner join requests & pending invites

| Spec | What it proves |
|------|----------------|
| `spec/requests/guild_alliance_join_requests_spec.rb` | **`GET …/alliance_join_requests/new`**: paid owner **200**; stranger to **`guild_id`** → **`my_guilds_path`** + **`controllers.guilds.access_denied`**. **`alliances_guild_search`** JSON: **403** without / wrong **`guild_id`**. |
| `spec/requests/guild_alliance_invites_spec.rb` | **`GET …/alliance_invites/pending`**: paid owner **200**; stranger → **`my_guilds_path`** + **`access_denied`**. |

## Alliance — member directory & polls (web)

| Spec | What it proves |
|------|----------------|
| `spec/requests/alliance_members_spec.rb` | **`GET …/alliance_members`**: OK for signed-in alliance member; response includes **`I18n.t('alliance_members.index.title')`**. Member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 314**, **Lane C**. **`DELETE …/remove`**: custom managers vs protected targets / other guilds. |
| `spec/requests/alliance_polls_spec.rb` | Poll index/show, voting JSON, anonymous vs named voters; index body includes **`I18n.t('alliance_polls.index.title')`**. **`GET …/alliance_polls`**: member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 315**, **Lane C**. **`GET …/alliance_polls/:id`**: member chrome **`support_center_url`** (same matrix — **changelog 316**, **Lane C**). Open **`GET …/alliance_polls/:id`**: **`data-controller="alliance-poll-vote"`**, **`data-alliance-poll-vote-poll-id-value`**, no **`window.location.reload`**; closed polls omit controller (**mega #151**). **`POST …/vote`**: **`voters_by_choice`** when not anonymous; **`AlliancePollsChannel.broadcast_to`** **`vote_update`** (**mega #152**). **`AllianceNestedAccess`**: unknown **`alliance_id`** or paid non-member → **`dashboard_path`** + **`controllers.guilds.access_denied`**. |
| `spec/channels/alliance_polls_channel_spec.rb` | **`AlliancePollsChannel`**: active **`AllianceMember`** subscribes with **`alliance_poll_id`**; rejects outsider / invalid id (**mega #152**). **`.broadcast_vote_update`** builds **`vote_update`** payload (**mega #154**). |
| `spec/requests/alliance_loot_rolls_spec.rb` | Loot roll index/create/enter/close; custom managers vs officers. **`AllianceNestedAccess`** on index: unknown **`alliance_id`** or paid non-member → **`dashboard_path`** + **`controllers.guilds.access_denied`** (**mega #109**). **`GET …/alliance_loot_rolls`**: member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 317**, **Lane C**. **`GET …/alliance_loot_rolls/:id`**: member chrome **`support_center_url`** (same matrix — **changelog 318**, **Lane C**); **`data-controller="alliance-loot-roll-live"`** + **`AllianceLootRollsChannel`** subscription id (**mega #157**). |
| `spec/requests/alliance_activity_feed_spec.rb` | **`GET …/activity_feed`** (`AllianceActivityFeedsController#index`): guild owner in alliance **200**; non-owning member → **`alliance_path`** + **`alliance_activity_feed.access_denied`**. Member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 319**, **Lane C**. **`GET …/export`** / **`export.json`**: CSV / JSON for owner (**`send_data`** / **`render json`** — no HTML chrome). |
| `spec/requests/alliance_disband_votes_spec.rb` | **`GET …/alliance_disband_votes`**: **200** for alliance **GM** (guild owner with active guild in alliance); non-GM member → **`alliance_path`**. Member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 320**, **Lane C**. **`POST`**: minority vote vs majority disband (**`AllianceDisbandVote`**). |
| `spec/requests/alliance_events_spec.rb` | Web RSVP + owner **`POST`** create; officers blocked from **`POST`**. **`GET …/alliance_events`** (**`AllianceEventsController#index`**): member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 323**, **Lane C**. **`GET …/alliance_events/new`**: same matrix — **changelog 321**, **Lane C**. **`GET …/alliance_events/:id`** (**`#show`**): same matrix — **changelog 322**, **Lane C**. |

## Guild polls (web)

| Spec | What it proves |
|------|----------------|
| `spec/requests/polls_spec.rb` | Index/new/create/show/voting; signed-in **`GET …/polls`** — **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 289**); **`GET …/polls/new`** — same matrix — **changelog 308**, **Lane C**; **`GET …/polls/:id`** — same matrix — **changelog 307**, **Lane C**; open **`GET …/polls/:id`** includes **`data-controller="poll-vote"`**, **`click->poll-vote#vote`**, **`data-poll-vote-poll-id-value`**, and **`data-poll-vote-vote-url-value`** (no pathname parsing; **`PollsChannel`** subscription) (**mega #150**, **#158**). |

## Guild loot rolls (web)

| Spec | What it proves |
|------|----------------|
| `spec/requests/loot_rolls_spec.rb` | Index/new/create/show/close/reroll; signed-in **`GET …/loot_rolls`** — **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 290**); **`GET …/loot_rolls/new`** — same matrix — **changelog 308**, **Lane C**; **`GET …/loot_rolls/:id`** — same matrix — **changelog 307**, **Lane C**; **`GET …/loot_rolls/:id`** includes **`data-controller="loot-roll"`** and **`data-loot-roll-loot-roll-id-value`** so **`LootRollController`** subscribes to **`LootRollsChannel`** (**mega #156**). |

**Developer map:** [`systems/guild_polls_loot_rolls.md`](../systems/guild_polls_loot_rolls.md) — routes, **`before_action`** order, **`PollPolicy`** vs **`LootRollPolicy`**, Cable payloads, **`DiscordPollService`** / **`DiscordLootRollService`**, matrix spec pointers (**mega #210**).

## Action Cable — guild polls & loot rolls (subscription)

**Client:** Stimulus controllers (`poll-vote`, `alliance-poll-vote`, `loot-roll`, `alliance-loot-roll-live`, `alliance-chat`) use **`app/javascript/cable_consumer.js`** **`getCableConsumer()`** — one WebSocket per tab; disconnect only **`subscription.unsubscribe()`** (**mega #159**).

| Spec | What it proves |
|------|----------------|
| `spec/channels/polls_channel_spec.rb` | **`PollsChannel`**: active guild member subscribes with **`poll_id`**; rejects outsider, **`poll_id` 0**, or missing poll (**`find_by`**, **mega #153**). |
| `spec/channels/loot_rolls_channel_spec.rb` | **`LootRollsChannel`**: active guild member subscribes with **`loot_roll_id`**; rejects outsider, id **0**, or missing loot roll (**mega #153**). **`.broadcast_update`** — unified **`loot_roll_update`** (**`entries`**, **`winner_id`**, **`has_tie`**, **`currently_open`**, anonymous **`display_name`** masking) (**mega #155**, **#156**). |
| `spec/channels/alliance_loot_rolls_channel_spec.rb` | **`AllianceLootRollsChannel`**: active **`AllianceMember`** subscribes with **`alliance_loot_roll_id`**; rejects outsider / invalid id (**mega #157**). **`.broadcast_update`** — **`alliance_loot_roll_update`** (**`mask_name`**, optional **`user_id`** when not anonymous, **`currently_open`**). |

## Alliance messages (web)

| Spec | What it proves |
|------|----------------|
| `spec/requests/alliance_messages_spec.rb` | **`GET …/alliance_messages`** (**`all_members`**): member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 312**, **Lane C**. **`GET …/alliance_messages`** (**`type=gm`**, guild owner / alliance GM): same **`support_center_url`** matrix — **changelog 313**, **Lane C**. Members **200**; GM-only **`type=gm`** vs owners; no **`window.location.reload`**; **`appendMessageRow`** + **`pollNewMessages`**; **`data-controller="alliance-chat"`** + **`alliance-chat:message`**; **`alliance-chat:connected`** / **`:disconnected`** + **`POLL_MS_WITH_CABLE`** (**30s** poll when Cable up, **5s** fallback) (**mega #149**). **`GET …/alliance_messages.json`**: **`since_id`** delta + empty cases; GM JSON **403** for non-owners (**mega #147**). **`POST`**: create + append JSON keys (**mega #146**); **`ActionCable.server.broadcast`** (**mega #148**). Timestamps: **`locale: :de`** + **`pageLocale`** (**mega #144**, **#145**). |
| `spec/channels/alliance_messages_channel_spec.rb` | **`AllianceMessagesChannel`**: **`all_members`** confirmed for active **`AllianceMember`**; **`gm_only`** vs non-GM / owners; invalid **`message_type`**; **`alliance_id` 0** or unknown alliance — all **`reject`** without streaming (**mega #148**, **#153**). |

## Alliance — free-tier retained members

| Spec | What it proves |
|------|----------------|
| `spec/requests/alliance_free_member_access_spec.rb` | **Free** user with active **`AllianceMember`**: read + participate (events, polls, loot, messages); create polls/events/loot blocked; **`alliances_guild_search`** **403**. **`GET …/activity_feed`** (+ **`/export`**, **`/export.json`**): non-owning free member → **`alliance_path`** + **`alliance_activity_feed.access_denied`**; **alliance leader** on **Free** **`PricingPlan`** → **200** / **`text/csv`** / JSON (**`RequiresPaidPlanForAllianceFeatures`** exemption + **`alliance_owner_in_active_guild?`**). **`…/alliance_disband_votes`**: free non-GM → **`alliances.disband_votes.errors.not_gm`**; **Free** leader (two active **`AllianceGuild`** rows) **GET** **200** + **POST** vote without majority disband. |

## Infrastructure — database backup to S3 (opt-in)

| Spec | What it proves |
|------|----------------|
| `spec/services/database_backup_to_s3_service_spec.rb` | **`DatabaseBackupToS3Service`**: disabled unless **`DATABASE_BACKUP_TO_S3_ENABLED=1`**; errors for missing bucket / credentials / **`pg_dump`** failure; success path stubs **`pg_dump`** + **`Aws::S3::Client#put_object`**. **`list_recent_backups`**: **`continuation_token`** forwarded to **`list_objects_v2`**; **`next_continuation_token`** on **`RecentBackupList`**; **`sanitize_list_continuation_token_param`** (blank / oversize **8 KiB**); sort within page; **`AccessDenied`** → **`failed`**. |
| `spec/jobs/database_backup_to_s3_job_spec.rb` | **`DatabaseBackupToS3Job`** calls the service; does not raise on service error (logs only). |
| `spec/requests/admin/database_backups_spec.rb` | **`GET /admin/database-backups`**: DB + config sections; **`Turbo-Frame: admin_database_backups_main`** → layoutless **`database_backups_show_frame`** (omits page title); **`list_recent_snapshots`** + **`config_continuation_token`**; oversized **`config_continuation_token`** → **`nil`**; config object table; DB next link retains **`config_continuation_token`**; **`list_recent_backups`** + **`continuation_token`**; unauthenticated → **`admin_login_path`**. |

## Infrastructure — config snapshot to S3 (opt-in)

| Spec | What it proves |
|------|----------------|
| `spec/services/config_snapshot_to_s3_service_spec.rb` | **`ConfigSnapshotToS3Service`**: disabled unless **`CONFIG_SNAPSHOT_TO_S3_ENABLED=1`**; bucket / credential errors; empty archive guard; success stubs **`build_archive_bytes`** + **`put_object`** + **`Rails.cache.write`**; **`relative_paths_for_snapshot`** includes **`config/initializers/*.rb`** and **`config/locales/**/*.yml`** (e.g. **`en/models.en.yml`**, **`en/devise.en.yml`**, **`en/en.yml`** catch-all); **`list_recent_snapshots`**: **`continuation_token`** → **`list_objects_v2`**; **`AccessDenied`** → **`failed`**. |
| `spec/jobs/config_snapshot_to_s3_job_spec.rb` | **`ConfigSnapshotToS3Job`** calls the service; does not raise on service error. |

## Guild file storage (plan + membership)

| Spec | What it proves |
|------|----------------|
| `spec/requests/storage_spec.rb` | **`StorageController`**, **`FoldersController`**, **`FileEntriesController`**: **`guild_id`** must belong to **`current_user`** (member, owner, or owned guild); else **`controllers.guilds.access_denied`** (**`my_guilds_path`** or **`404` JSON**). **`GET …/storage`**: **`file_storage`** entitlement (**Upgraded**+); fixture users use **`skip_free_plan_subscription`** + **Upgraded** **`Subscription`** so **`current_plan`** matches YAML; member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 286**, **Lane C**. **`POST …/folders`**: **`ParameterMissing`** stub → **400** **`controllers.folders.missing_required_parameter`** (**mega #118**). |

## Guild Discord role matrix (owner + slots)

| Spec | What it proves |
|------|----------------|
| `spec/requests/guild_permissions_matrix_spec.rb` | Single-slot examples: members list, settings, **applications** (**`GET …/members/invite`**, **`GET …/applications`**, **`POST …/invite_links`**, **`can_manage_applications?`** / **`applications_denied`**), schedule_events (owner-only), activity feed, message center, guild warnings, members CSV, **update member role** (**`PATCH …/update_role`**, **`can_manage_roles?`** / **`roles_denied`**), **bulk kick** + **bulk update roles** (**`POST …/bulk_kick`**, **`POST …/bulk_update_roles`**, **`kick_denied`** / **`bulk_kicked`**, **`roles_denied`** / **`bulk_role_updated`**), **kick member** (**`DELETE …/members/:id`**, **`can_kick_members?`** / **`kick_denied`**), **create tag** + assign + **remove tag** (**`can_manage_tags?`**), **invite user** (**`POST …/invite_user`**, **`can_manage_roles?`** / **`invite_denied`**) + **user search** (**`GET …/users/search`**, **403** **`roles_denied`** vs **200**) + **Discord role sync JSON** (**`GET …/discord_roles`**, same **`can_manage_roles?`**; **`discord_roles_spec`** non-member **404**), polls, loot rolls, documents (**Upgraded** officer), **gear request** (**`POST …/gear/request`**, **`can_manage_gear_requests?`** false → **403** **`I18n.t("api.v1.not_authorized")`** — **mega #122**), file storage folder JSON, **Discord events** **`new`**, **Discord channel PATCH** + **`GET …/discord/connect`** (**`DiscordConnectionsController`**, **`can_manage_discord_channels?`** vs **`discord_channels_denied`** / **200**). **`spec/requests/discord/connections_spec`**: **`GET /discord/oauth/callback`** re-runs **`can_manage_discord_channels?`** before **`exchange_code_for_token`** (revoked flag → no token exchange). **`spec/requests/discord/bot_authorization_flow_spec`**: bot callback **`bot_callback_handler`** — no Discord token **`POST`** if **`can_manage_discord_channels?`** false after **`connect_server`**. Default officer plan: **Basic**. |
| `spec/requests/guild_role_permissions_grid_spec.rb` | Combinatorial 18 flags × 4 slots (see file header). Subscriptions use an **Upgraded**-named **`PricingPlan`** so plan gates (`activity_feed`, `warnings`, `message_center`, `guild_documents`, `file_storage`, `ai_gear_scanner`, …) succeed before role-only allow/deny assertions. **`can_manage_gear_requests`**: **`POST …/gear/request`** deny → **`api.v1.not_authorized`**; allow path JSON **`error`** ≠ that key (**mega #122**). |
| `spec/requests/guild_owner_trumps_role_flags_spec.rb` | Owner still reaches gated routes when **all** `role_*` flags are false and `permission_role_*` cleared; uses **Upgraded** plan for plan-gated routes. |
| `spec/requests/discord_roles_spec.rb` | **`DiscordRolesController`** JSON: **`GET …/discord_roles`** list + **`connected_at`** cleared → **422** **`api.discord.not_connected`**; **`POST …/discord_roles/sync`** missing **`role_id`/`role_name`** → **422** **`discord_roles.api.role_id_and_name_required`**; **201** new sync → **`discord_roles.api.synced_successfully`** (**mega #117** + **#118** regression lock); **`POST …/sync_all`** message **`discord_roles.api.synced_roles_count`**; stranger **404** **`access_denied`**. |
| `spec/requests/api/v1/discord_spec.rb` | **`GET …/discord/channels`**: pagination (owner); **`connected_at`** cleared → **422** **`api.discord.not_connected`**; slot + flag **200** / flag off **403** **`api.v1.not_authorized`**. **`PATCH …/discord/channels`**: owner persists **`events_channel_id`** + **`api.discord.channels_updated`**; officer with slot + flag persists **`gear_channel_id`**; flag off **403** and no change. **`POST …/discord/events/:event_id/signup`**: **200** + **`api.discord.signup_success`** + job; missing **`discord_username`** → **422** **`api.discord.missing_discord_identity`**; **`event_id`** **0** → **404** **`api.discord.event_not_found`**; non-member **404** **`access_denied`**; **inactive** member **403** **`api.v1.not_authorized`**. |
| `spec/models/guild_spec.rb` | **`#role_permission_enabled_for?`** encodes owner bypass and slot + **`GuildMember#discord_role_id`** checks (used by policy and delegated from **`ApplicationController`**). |

## Messaging and warnings

| Spec | What it proves |
|------|----------------|
| `spec/requests/message_center_isolation_spec.rb` | **`GET …/message_center`**: member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 284**, **Lane C**. Non-member → **`my_guilds_path`** + **`controllers.guilds.access_denied`** (scoped **`set_guild`**); no slot permission; invalid recipient on **send** and **`GET …/conversation/:recipient_id`** (**`message_center.invalid_recipient`**); **guild-scoped** conversation (`guild_id` filter); persisted `guild_id` for in-guild DMs. |
| `spec/requests/activity_feed_spec.rb` | **`GET …/activity_feed`**: member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 283**, **Lane C**. **`GET …/activity_feed/export`**: stranger → **`access_denied`** / **`my_guilds_path`**; CSV export + permission flag. |
| `spec/requests/guild_warnings_spec.rb` | **`GET …/warnings`** (managers) and **`GET …/warnings/me`** (members): member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 285**, **Lane C**. Manager vs member; protected targets; **Basic** subscription in setup (plan gate runs before role checks); isolation: no guild access, non-member `user_id` on create. |

## Guild archives (owner-only, retention purge)

| Spec | What it proves |
|------|----------------|
| `spec/requests/guild_archives_spec.rb` | Archive with guild name confirmation; wrong name → no archive; archived guild **`show`** / message center → **`guild_archives_path`**; index lists owner’s archived guilds; **`GET /guild_archives`** asserts **`guild_archives.index`** recovery copy (**`locale=en`** query regressions exclude legacy inverted phrasing); **`?locale=de`** smoke for translated recovery strings; member chrome **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 296**, **Lane C**; unarchive blocked at plan limit; **`DELETE`** purge only after **`scheduled_purge_at`**; **non-owner member** cannot archive (**`owner_only`**); **no guild access** → **`access_denied`**; **stranger** cannot unarchive/purge another owner’s archived guild (**`not_found`**); unauthenticated **index** / **archive** → **`login_path`**. |

## Recruiting name blocklist (public listing)

| Spec | What it proves |
|------|----------------|
| `spec/services/recruiting_visibility_service_spec.rb` | `RecruitingVisibilityService.publicly_recruitable?` for strings and `Guild`; case-insensitive substring match; every `BLOCKLIST` entry is covered; **`matching_severe_terms`** for roadmap / shared substring logic. |
| `spec/models/guild_spec.rb` | `apply_recruiting_visibility_for_name` forces `publicly_listed` false when the name hits the blocklist. |
| `spec/requests/guilds_spec.rb` | **`GET /guilds`** (**`my_guilds_path`**): signed-in member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 280**, **Lane C**. **`GET /guilds/new`** (**`GuildsController#new`**): same **`support_center_url`** matrix — **changelog 306**, **Lane C**. New-guild form includes `guilds.new.recruiting_name_warning` when the typed name would be hidden. |

## Marketing — home landing (guest `GET /`)

| Spec | What it proves |
|------|----------------|
| `spec/requests/home_landing_spec.rb` | Guest **`GET /` (`root_path`, `HomeController#landing`)** — footer documentation/contact links use **`support_center_url`**: default **`SiteSetting::DEFAULTS["release_notes_url"]`** in HTML; same with **`MobileVariantRequestHelpers`** **`:mobile`** User-Agent; admin-configured **`release_notes_url`** in HTML (desktop + **`:mobile`**) — **changelog 273**, **Lane C**; marketing CMS: **`home.landing.features_cta_hint`** as semantic **`h2`** (exact EN marketing line asserted), **`landing-feedback-carousel`** when **`LandingUserFeedback`** rows exist, feature grid **`pt-0`** vs **`pt-16`** vs feedback presence; **`homepage_feature_path("member_management")`** when a card exists (**2026-04-06**). Cross-map: **`systems/site_settings_support_url.md`** (**mega #191**), **`systems/home_landing_marketing_cms.md`**. |
| `spec/requests/homepage_features_spec.rb` | Public **`GET /features/:slug`** (`HomepageFeaturesController#show`): **200** + rich **`ActionText`** body; **`<title>`** from layout **`content_for :page_title`** (`{card title} — {app_name}`); **`meta name="description"`**, **`og:type`**, **`og:url`**, **`og:title`**, **`og:description`**, **`og:image`**, **`twitter:card`**, **`twitter:title`**, **`twitter:description`**, **`twitter:image`**, **`rel="canonical"`**; **404** when **`visible: false`** or unknown slug; **`:mobile`** variant (**`MobileVariantRequestHelpers`**) → Inter font link + marketing flush shell (not generic card wrapper). Cross-map: **`systems/home_landing_marketing_cms.md`**. |
| `spec/i18n/home_landing_feedback_i18n_spec.rb` | Guest carousel copy: **`home.landing.feedback.*`** keys (**`section_title`**, roles, **`announce_progress`**, nav labels, **`pagination`**, **`go_to_slide`**) exist and are non-blank in every **`I18n.available_locales`** (**`fallback: false`**); **`go_to_slide`** includes the interpolated index. Cross-map: **`systems/home_landing_marketing_cms.md`**. |

## Pricing — signed-in upgrade (`GET /pricing/upgrade`)

| Spec | What it proves |
|------|----------------|
| `spec/requests/pricing_spec.rb` | Signed-in **`GET /pricing/upgrade`** (`PricingController#upgrade`, **`pricing/upgrade`**) — contact copy includes **`support_center_url`**: default **`SiteSetting`**, custom admin URL, desktop + **`:mobile`** (**changelog 274**, **Lane C**). **`GET /pricing`** redirect to upgrade when signed in — existing examples. Cross-map: **`systems/site_settings_support_url.md`** (**mega #191**), **`systems/pricing_plans.md`** (**mega #222**). |

## Roadmap (feature requests + comments)

| Spec | What it proves |
|------|----------------|
| `spec/requests/roadmap_spec.rb` | **`GET /roadmap` (HTML):** guest shows **`roadmap.subtitle`**, **`roadmap.guest_footer_note`**, and does **not** include **`layouts.application.dropdown.release_notes_instructions`**; same guest chrome on **`:mobile`** (**`MobileVariantRequestHelpers`** — **changelog 264**, **Lane C**). Signed-in shows **`roadmap.signed_in_create_hint`**, **`roadmap.moderation_rules_notice`**, **`roadmap.release_notes_link`**, with the same omission of dropdown release-notes copy (**changelog 244**, **Lane C**); same signed-in chrome on **`:mobile`** (**changelog 265**, **Lane C**); signed-in **`support_center_url`** on release-notes link (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 276**, **Lane C**; signed-in **`GET /roadmap/:id` (HTML)** member chrome **`support_center_url`** (same matrix) — **changelog 301**, **Lane C**. Guest title HTML-escape in **`release_notes_spec`** (**changelog 260**); guest **`GET /roadmap`** **`:mobile`** — **changelog 266**. Create + comments: profanity → **`moderation_status`** `pending`; **severe `RecruitingVisibilityService::BLOCKLIST`** in title/body → **`pending`** even without profanity hit; public **show** omits pending comments. **Map:** **`systems/feature_requests_roadmap.md`** (**mega #195**). **`POST /roadmap/requests` (Turbo Stream):** approved → **`append`** **`roadmap_column_list_considering`**; **`q`** mismatch → no append + **`roadmap.create.filtered_board_hint`**; invalid → **422** **`roadmap_modal_form_errors`**; pending title → notice stream, no append. **`POST …/comments` (Turbo Stream):** approved → **`append`** **`roadmap_comments_list`** + count; pending → moderation notice **without** pending body; empty → **422** + **`roadmap_comment_form_errors`**. **`DELETE …/roadmap/comments/:id` (Turbo Stream):** **`remove`** row + count; last visible → **`roadmap-comments-empty`**; **403**/**404** → form errors; JSON **`ok`**. **`GET …/roadmap/:id` (JSON):** unknown id → **404** + **`roadmap.not_found`** (**mega #119**). **`POST` vote (JSON):** guest **401** + **`error`** (Devise); signed-in bad id → **`I18n.t("roadmap.vote.not_found")`**; toggle vote + **`vote_count`**. |
| `spec/requests/guild_member_management_spec.rb` | Members list **`guilds.members.tags.*`** filter labels and **`clear_filter`** when **`tag_id`** is set (i18n, no inline **`default:`**). **`GET /guilds/:id/members`** member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 297**, **Lane C**. **`GET /guilds/:id/review_applications`** — same **`support_center_url`** matrix — **changelog 298**, **Lane C**. **`GET /guilds/:id/members/invite`** (`invite_members`) — same — **changelog 299**, **Lane C**. |
| `spec/models/feature_request_spec.rb` | Severe blocklist + profanity merge into **`moderation_triggered_words_list`**. |
| `spec/models/feature_request_comment_spec.rb` | Severe blocklist in body → **`pending`**. |

## Search, react roles, Discord event signup webhook

| Spec | What it proves |
|------|----------------|
| `spec/requests/search_spec.rb` | **`GET /search`**: when **`perform_search`** raises, **500** JSON **`error`** = **`controllers.search.search_failed`** (**mega #119**). |
| `spec/requests/react_roles_spec.rb` | **`PATCH …/react_roles`**: stranger → **404** + **`controllers.guilds.not_found`**; member without guild-settings permission → **403** + **`api.v1.not_authorized`** (**mega #119**). |
| `spec/requests/discord_event_signups_spec.rb` | **`POST /discord/event_signups/webhook`** (no session; **`ApplicationController#public_page?`** includes **`discord_event_signups#webhook`**): missing params / unknown event / bad role → **400**/**404** + **`controllers.discord_event_signups.webhook.*`**; valid **`dps`** payload → **200** + signup count (**mega #119**). |
| `spec/requests/discord/connections_spec.rb` | **`GET /guilds/:id/discord/connect`** (`DiscordConnectionsController#show`, **`guild_connect_discord_path`**): member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 300**, **Lane C**; OAuth popup/callback, **`can_manage_discord_channels?`** re-check, server select — existing examples. |
| `spec/requests/events_bot_integration_spec.rb` | **`GET /guilds/:id/events/schedule`** (`GuildsController#schedule_events`): Discord scheduled-event UI + bot API stubs; signed-in owner — member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 291**, **Lane C**. **`GET /guilds/:id/discord_events/new`** (`DiscordEventsController#new`, bot + user Discord + events channel stubs): same **`support_center_url`** matrix — **changelog 304**, **Lane C**. **`GET /guilds/:id/discord_events/:id`** (`DiscordEventsController#show`): same matrix — **changelog 305**, **Lane C**. **`POST …/discord_events`** creates **`DiscordEvent`**, posts signup message. |
| `spec/requests/guild_documents_spec.rb` | **`GET …/documents`** (owner with manage permission): member chrome includes **`support_center_url`** (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 287**, **Lane C**. **`GET …/documents/new`** (owner): same matrix — **changelog 309**, **Lane C**. **`GET …/documents/:id`** (guild member): same matrix — **changelog 310**, **Lane C**. **`GET …/documents/:id/edit`** (owner): same matrix — **changelog 311**, **Lane C**. **`POST …/documents/autosave`** with **`id`**: officer with **`can_manage_documents?`** but not creator/owner/admin → **403** + **`api.v1.not_authorized`** (**mega #119**). |

## Discord gateway — bot interactions (`POST /discord/webhooks`)

| Spec | What it proves |
|------|----------------|
| `spec/requests/discord/webhooks_interactions_spec.rb` | **`DiscordWebhooksController#interactions`**: signed **`MESSAGE_COMPONENT`** with unknown **`custom_id`** prefix → **200** type **4** ephemeral **`discord.webhooks.unknown_interaction_type`** (**mega #123**); RSVP button flows (**type 5** deferred); poll/loot dispatch to **`DiscordInteractionJob`**. **2026-04-05:** **`discord.webhooks.rsvp` / `alliance_rsvp` / `event_embed`** present for every **`I18n.available_locale`** (**mega #124**); **`event_details_{id}`** → **type 4** ephemeral with **`discord.webhooks.legacy_event_details.*`** (**mega #125**). **`guild_event_rsvp_access_spec`**, **`alliance_event_rsvp_interactions_spec`** — access / alliance RSVP with stubbed signature + follow-up. |


| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/guild_transfers_spec.rb` | **`GET …/new`**: title outside **`turbo-frame`** **`admin_guild_transfers_new_main`**; **`GET`** with **`Turbo-Frame: admin_guild_transfers_new_main`** → frame-only HTML (**`layout: false`**), no page title in body — **mega #225**. Full **`GET`** still includes **`admin.guild_transfers.new.page_title`**, **`guild_with_name`**, **`transfer_submit`** (**mega #134**). **POST create** moves **`Guild#owner`**, audit log; optional **`cancel_previous_owner_billing`** + **`SubscriptionCancellationService`** when previous owner has **no** other active owned guilds; unauthenticated **new** / **create** → **`admin_login_path`**. **`POST …/create`** with **`Accept: text/vnd.turbo-stream.html`**: **`303`** **`see_other`** → **`admin_user_path(new_owner)`** + transferred notice (**mega #178**). **`guild_ownership_transfer_service_spec`** covers service outcomes. |

## Admin — sessions

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/sessions_spec.rb` | **`GET /admin/login`**: credential form inside **`turbo-frame`** **`admin_sessions_login_main`** (**`_sessions_new_main`**); **`Turbo-Frame: admin_sessions_login_main`** → layoutless **`sessions_new_frame`** — **mega #232**. **`admin.sessions.login_heading`**, **`email_label`**, **`password_label`**, **`submit`**, **`secure_notice`** (**mega #130**). **`POST /admin/login`** failure body includes **`I18n.t("admin.sessions.invalid_credentials")`** (**mega #126**); success sets `session[:admin_authenticated]`; **`GET /admin/login`** when already admin → dashboard; member signed-in **GET** login hides **`#sidebar`** + shows **`layouts.application.nav.back_to_member_dashboard`**; **`DELETE /admin/logout`** clears admin session. |

## Admin — dashboard

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/dashboard_spec.rb` | **`GET /admin`**: stats + **`I18n.t`** for **`paying_subscribers`**, HTML-escaped **`trials_and_free`**; critical-feature tiles (**`system_monitoring`**, **`ocr_requests`**); quick actions (**`release_note_link_updater`**, **`beta_features`**, **`database_backups`**). **`Turbo-Frame: admin_dashboard_index_main`** → layoutless **`dashboard_index_frame`** (omits page **`h1`** title); in-frame links use **`data-turbo-frame="_top"`** so navigation replaces the full page. Dashboard i18n sweep (**`admin.dashboard`**, incl. **`restore_user`** tile non-EN) — **mega #138**; Turbo main frame — **mega #218**. |
| `spec/i18n/javascript_admin_dashboard_spec.rb` | **`js.admin.dashboard.delete_success`** / **`delete_error`** / **`delete_failed`**: every **`I18n.available_locales`** translation must not contain **`TODO_ADMIN`** (admin danger-zone delete toasts from **`javascript.{locale}.yml`**) — **mega #139**. |

## Admin — subscription directory (paying / trials)

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/subscriptions_spec.rb` | **`GET …/subscriptions/paying`** / **`trials`**: page titles + cross-links use **`admin.subscriptions.paying_users.*`** / **`trial_users.*`**; shared search chrome from **`admin.users.index.*`**; **`?locale=de`** renders German **`page_title`**. Search **`form_with`** targets **`Turbo-Frame`** **`admin_subscriptions_paying_main`** / **`admin_subscriptions_trial_main`**; **`GET`** with that header → **`layout: false`** fragment (no page **`h1`**). **`GET …/paying/search`** / **`trials/search`**: **`status`** uses **`admin.users.show.subscription_status.*`**; missing plan → **`admin.subscriptions.json.no_plan`** (**mega #140**, **#181**). |

## Admin — audit log

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/audit_logs_spec.rb` | **`GET /admin/audit_logs`**: **`admin.audit_logs.index.page_title`**, **`record_line`** for typed records; **`?locale=de`** German title; **`Turbo-Frame: admin_audit_logs_results`** → frame-only index table (**mega #193**). **`GET /admin/audit_logs/:id`**: title + back outside **`turbo-frame`** **`admin_audit_logs_show_main`**; **`Turbo-Frame: admin_audit_logs_show_main`** → frame-only detail (**`layout: false`**) — **mega #227**. Full show still includes **`admin.audit_logs.show.page_title`** + **`record_line`** (**mega #141**). |

## Admin — error tracker

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/errors_spec.rb` | **`GET /admin/errors`**: unresolved/resolved columns + **`admin_errors_flash`** / **`admin_errors_columns`** ids (**mega #172**). **`GET /admin/errors/:id`**: full page wraps **`turbo-frame`** **`admin_errors_show_main`** around **`admin_error_show_flash`** + **`admin_error_show_main`**; **`Turbo-Frame: admin_errors_show_main`** → frame-only **`errors_show_frame`** (**`layout: false`**) — **mega #228**. **`POST …/errors/bulk`** with **`Accept: text/vnd.turbo-stream.html`**: **`replace`** columns + notice; empty **`error_ids`** → flash alert stream. **`DELETE …/errors/:id`** with Turbo + **`Referer`** index URL → column refresh (**mega #172**). **`POST …/errors/:id/resolve`** with Turbo on **show**: **`update`** **`admin_error_show_flash`** + **`replace`** **`admin_error_show_main`** + resolved copy in stream (**mega #173**). HTML resolve redirect + **`admin.errors.flash.*`** unchanged. Cross-map: **`overall/error_observability.md`** (**mega #196**). |

## Jobs — error Discord notify

| Spec | What it proves |
|------|----------------|
| `spec/jobs/error_discord_notify_job_spec.rb` | **`ErrorDiscordNotifyJob`**: missing **`ErrorLog`**, webhook **`RestClient.post`**, DM path with stubbed **`DiscordService`**, truncation / failure absorption. Cross-map: **`overall/error_observability.md`** (**mega #196**). |

## Admin — pricing plan features (plan cards)

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/pricing_plan_features_spec.rb` | **`GET /admin/pricing-plan-features`**: title + subtitle outside **`turbo-frame`** **`admin_pricing_plan_features_main`**; frame wraps flash + form. **`GET`** with **`Turbo-Frame: admin_pricing_plan_features_main`** → frame-only HTML (**`layout: false`**), no page title in body — **mega #224**. **`PATCH`**: happy paths, **`invalid_monthly_price`**, **`validation_error`** wrapper when **`price_display`** blank (**`RecordInvalid`**, **mega #130**). **`PATCH`** with **`Accept: text/vnd.turbo-stream.html`**: **`update`** flash target + **`replace`** form wrap + persisted feature lines (**mega #176**); invalid monthly + Turbo → **`303`** **`/admin/pricing-plan-features`**. |

## Admin — landing compare (marketing tables)

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/landing_compare_spec.rb` | **`GET /admin/landing-compare`**: full page has title outside **`turbo-frame`** **`admin_landing_compare_main`**; frame holds **`admin_landing_compare_flash`** / **`admin_landing_compare_form_wrap`**. **`GET`** with **`Turbo-Frame: admin_landing_compare_main`** → frame-only HTML (**`layout: false`**), no page title in body — **mega #221**. **`PATCH`** success: HTML redirect + notice (**unchanged**). **`PATCH`** with **`Accept: text/vnd.turbo-stream.html`**: **`update`** flash + **`replace`** form wrap; body includes saved section title / row labels + **`admin.landing_compare.updated`** (**mega #174**). Validation failure + Turbo → **`303`** redirect with alert (same as roadmap unauth pattern). |

## Admin — landing marketing CMS (guest home + feature pages)

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/landing_marketing_cms_spec.rb` | Unauthenticated **`GET`** index / **new** / **edit**, **`POST` create**, **`PATCH` update**, **`DELETE`**, and **`PATCH …/reorder`** on **`/admin/landing-user-feedbacks`** and **`/admin/homepage-feature-cards`** → **`admin_login_path`** (no rows created / updated / destroyed / reordered). Authenticated admin: dashboard quick actions; **CRUD** + **reorder** (**`PATCH …/reorder`** **200** only for a full id permutation, else **422**); **26th** feedback create blocked; public preview + **`GET /features/:slug`**. Cross-map: **`systems/home_landing_marketing_cms.md`**. |
| `spec/requests/admin/landing_marketing_cms_management_spec.rb` | Signed-in admin: **`GET …/landing-user-feedbacks/new`** when **25** rows exist → redirect index + **`at_limit`** notice after **`follow_redirect!`**; feedback **PATCH** (visibility + body) + **DELETE**; feature card **PATCH** hides slug → public **`GET /features/:slug`** **404**; **DELETE** card → public **404**. Cross-map: **`systems/home_landing_marketing_cms.md`**. |
| `spec/requests/admin/landing_marketing_cms_reorder_spec.rb` | Signed-in admin: **`PATCH …/reorder`** **422** when feedback order omits a row or feature-card order includes an unknown id; positions unchanged. Cross-map: **`systems/home_landing_marketing_cms.md`**. |
| `spec/requests/home_landing_marketing_contract_spec.rb` | Guest **`GET /`**: exact EN feature-grid CTA line; feature card **`href="/features/:slug"`** + **`block h-full w-full`**; feedback **`h2`** **User Feedback**; carousel prev/next + dots when **>1** row (omitted for a single row); only **visible** feedback bodies in HTML; **`?locale=de`** → German **`aria-label`** strings for carousel controls; **25** slide targets when **`LandingUserFeedback::MAX_ENTRIES`** visible rows exist. Cross-map: **`systems/home_landing_marketing_cms.md`**. |

## Admin — site settings (support pages URL)

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/site_settings_spec.rb` | **`GET /admin/settings/release-notes`**: title outside **`turbo-frame`** **`admin_release_notes_main`**; frame wraps flash, form, and where-used card for **URL For Support Pages**. **`GET`** with **`Turbo-Frame: admin_release_notes_main`** → frame-only HTML (**`layout: false`**), no page title in body — **mega #223**. **`PATCH`** valid URL: HTML redirect + persisted value (**unchanged**). **`PATCH`** with **`Accept: text/vnd.turbo-stream.html`**: **`update`** **`admin_release_notes_flash`** + **`replace`** **`admin_release_notes_form_wrap`** + **`roadmap.admin.release_notes.updated`** in stream (**mega #175**). Invalid, malformed, or unsafe URL + Turbo → **`303`** to same path. Audit log on successful update unchanged. Cross-map: **`systems/site_settings_support_url.md`** (**mega #191**). |

## Member — `/release-notes` and in-app support links

| Spec | What it proves |
|------|----------------|
| `spec/requests/release_notes_spec.rb` | **`GET /release-notes`** redirects to **`SiteSetting`** default or custom **`release_notes_url`**; same **302** targets with **`:mobile`** User-Agent (**changelog 269**, **Lane C**). **`GET /support/contact`** (**`SupportController#contact`**, auth required) **302** to the same URL (default + custom **`SiteSetting`**); desktop + **`:mobile`** (**changelog 270**, **Lane C**). **Guests** — **302** does not **`Location`**-expose default or custom support host (desktop + **`:mobile`** + custom host — **changelog 271**; explicit guest custom URL **`:mobile`** — **272**, **Lane C**). Signed-in **dashboard** HTML includes configured URL for sidebar / nav “support” behavior; avatar dropdown label from **`I18n.t("layouts.application.dropdown.release_notes")`**; instructions line matched via **`ERB::Util.html_escape(I18n.t("…release_notes_instructions"))`** (template escapes **`>`** as **`&gt;`** — **changelog 262**). **Mobile variant** (**`MobileVariantRequestHelpers`** User-Agent → **`application.html+mobile.erb`**) — same dropdown strings (**changelog 263**, **Lane C**); **`GET /dashboard`** **`:mobile`** — default + custom **`release_notes_url`** in body (**changelog 267**, **Lane C**). **Guest `GET /roadmap`:** body includes **`ERB::Util.html_escape(I18n.t("roadmap.title"))`** (matches **`<h1>`** when the title contains **`&`**) and **`roadmap.guest_footer_note`**; same on **`:mobile`** (**changelog 266**, **Lane C**); the signed-in-only **`roadmap.release_notes_link`** card is absent on the guest index (**changelog 260**, **Lane C**). Cross-map: **`systems/site_settings_support_url.md`**, **`systems/feature_requests_roadmap.md`** (**mega #191** / **#195**). |

## Admin — content moderation

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/content_moderation_spec.rb` | **`GET /admin/content_moderation`**: page **`h1`** + **`admin_content_moderation_flash`** outside **`turbo-frame`** **`admin_content_moderation_index_main`**; tabs + tab panels in **`_content_moderation_index_main`**; tab **`link_to`** + profanity **view blocked words** use **`data-turbo-frame`** **`admin_content_moderation_index_main`**; back → **`_top`**. **`Turbo-Frame: admin_content_moderation_index_main`** → layoutless **`content_moderation_index_frame`** (omits **`page_title`**; **`tab`** respected) — **mega #234**. Body includes **`page_title`** on full document (**mega #132**). **`tab=blocked_words`** → **`tab_blocked_words`** + **`blocked_words_heading`**; **`tab=health`** → **`health_heading`**, **`run_manual_check`**. Profanity trigger, blocked-word add/remove; **with admin**, **POST run_health_check** enqueues **`ContentModerationHealthCheckJob.perform_async`**; **`POST …/run_health_check`** / **`trigger_profanity_update`** **`.turbo_stream`** → **`admin_content_moderation_health_wrap`** / **`admin_content_moderation_profanity_wrap`** + flash host (**mega #190**); **POST approve_content** / **hide_content** / **soft_delete_content** + flash **`admin.content_moderation.flash.*`** (**mega #126**); **without admin session**, mutating **POST**/**DELETE** redirect to **`admin_login_path`** where asserted. |

## Admin — trials, compliance, games, feature abusers

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/users_spec.rb` | **`GET /admin/users`**: body includes **`I18n.t("admin.users.index.page_title")`**, **`search_submit`**; restore referer flow includes **`user_id_prefix`** + **`use_for_restore`** (**mega #131**). **`GET /admin/users/:id`**: **`page_title`** outside **`turbo-frame`** **`admin_users_show_main`**; **`_users_show_main`** inside the frame (**`admin_user_show_flash`**, user card, trial + compliance panels); **`Turbo-Frame: admin_users_show_main`** → **`users_show_frame`** (**`layout: false`**) — **mega #229**; full show still includes **`trial_badge`**, **`subscription_status.trialing`** (**mega #135**). Turbo stream targets **`admin_user_show_flash`**, **`admin_user_subscription_trial_panel`**, **`admin_user_compliance_panel`** (**mega #169**, **#171**). **`PATCH …/trial`** with **`Accept: text/vnd.turbo-stream.html`**: panel **`replace`** + flash vs alert-only (**mega #171**). Trial extension / custom date: **`I18n.t("admin.users.trial_flash.*")`** (**mega #127**). |
| `spec/requests/admin/user_compliance_spec.rb` | Compliance actions (e.g. force logout): **`I18n.t("admin.user_compliance.flash.force_logout")`** (**mega #127**). **`Accept: text/vnd.turbo-stream.html`**: flash-only vs panel **`replace`** + lock/unlock button copy; reset-email **`admin_user_show_email`** (**mega #169**). **`GET …/login_history/:user_id`**: **`admin.user_compliance.login_history.*`** page title + column labels (**mega #142**). **`Turbo-Frame: admin_user_compliance_login_history_main`** → layoutless **`login_history_frame`** (omits page **`h1`**); back link + **`view_login_history`** use **`data-turbo-frame="_top"`** — **mega #220**. |
| `spec/requests/admin/games_spec.rb` | Approve / deny / reject / destroy pending games: **`admin.games.flash.*`** via **`I18n.t`** (**mega #127**). **`GET /admin/games`** / **`pending`**: **`admin.games.index.*`** / **`pending.*`** chrome (**mega #142**). **`Accept: text/vnd.turbo-stream.html`** on **approve** / **deny** / **reject**: **`remove`** row or **`replace`** **`admin_games_pending_content`** (empty queue) + flash (**mega #168**). |
| `spec/requests/admin/beta_features_spec.rb` | **`GET /admin/beta-features`**: list + search; body includes **`admin.beta_features.title`**; multi-page UI uses **`admin.beta_features.pagination_*`** when **`@total_pages > 1`** (**mega #142**). **`POST …/enable`** / **`…/disable`** with **`Accept: text/vnd.turbo-stream.html`**: **`replace`** row + enabled/disabled notice (**mega #166**). |
| `spec/requests/admin/feature_abusers_spec.rb` | **`GET`** index includes **`I18n.t("admin.feature_abusers.title")`**, **`col_email`** (**mega #137**, **#142**). **`locale: :pt`** / **`:it`** — body includes localized **`intro`** + **`search`** (**mega #143**). Lock / unlock: **`admin.feature_abusers.flash.locked`** / **`.unlocked`** (**mega #127**). **`POST`** lock/unlock with **`Accept: text/vnd.turbo-stream.html`**: **`replace`** row + flash (**mega #167**). Pagination **`admin.feature_abusers.pagination_*`** when multiple pages (**mega #142**). |
| `spec/requests/admin/feature_requests_spec.rb` | **`GET /admin/roadmap`**: panel title + search outside **`turbo-frame`** **`admin_feature_requests_main`**; board + **`admin_feature_requests_flash`** inside. **`Turbo-Frame: admin_feature_requests_main`** → layoutless **`feature_requests_index_frame`** (omits page title; Kanban still present) — **mega #230**. **`GET /admin/roadmap/:id/edit`**: page **`h1`** + back link outside **`turbo-frame`** **`admin_feature_requests_edit_main`**; form in **`_feature_requests_edit_main`** (**`data: { turbo: false }`** on **`PATCH`**). **`Turbo-Frame: admin_feature_requests_edit_main`** → layoutless **`feature_requests_edit_frame`** (omits **`h1`**) — **mega #231**. **`PATCH …/pin`** (Turbo Stream): **`replace`** card + pinned/unpinned (**mega #163**). **`DELETE …/roadmap/:id`**: **`remove`** + deleted flash; empty column id (**mega #164**). **`PATCH …/move`** (Turbo): empty target → **`remove`** **`admin_roadmap_empty_*`** + **`append`**; populated target → no empty **`remove`**; same **`status`** → flash only; bad **`status`** → **422** (**mega #165**). |

## Admin — OCR usage

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/ocr_requests_spec.rb` | **`GET …/ocr-requests`**: page **`h1`** + back + **`admin_ocr_requests_index_flash`** outside **`turbo-frame`** **`admin_ocr_requests_index_main`**; **`_index_main`** (stats, bulk table, search) inside **`admin_ocr_requests_index_main_wrap`**. **`Turbo-Frame: admin_ocr_requests_index_main`** → layoutless **`ocr_requests_index_frame`** (omits page title) — **mega #233**. **`admin.ocr_requests.index.title`** chrome (**mega #127**). Export CSV, row **view**, **clear search**, show **back to list** → **`data-turbo-frame="_top"`**. **`GET …/ocr-requests/:user_id`**: page **`h1`** + **`admin_ocr_user_show_flash`** outside **`turbo-frame`** **`admin_ocr_requests_show_main`**; **`_ocr_requests_show_main`** inside ( **`admin_ocr_user_summary_cards`**, actions, usage history). **`Turbo-Frame: admin_ocr_requests_show_main`** → layoutless **`ocr_requests_show_frame`** (omits **`show.title`**) — **mega #235**. **`ocr_user_refresh`** / **`ocr_user_flash_alert`** (**mega #170**) unchanged. **`POST …/adjust`** / **`toggle_lock`** with **`Accept: text/vnd.turbo-stream.html`**: full refresh streams vs alert-only when reason blank (skips if OCR columns absent). **`POST …/bulk`** **`.turbo_stream`** → **`ocr_requests_index_refresh`** (flash + **`admin_ocr_requests_index_main_wrap`** — **mega #192**). Bulk/export/auth as before. |

## Admin — database queries

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/queries_spec.rb` | **`GET /admin/queries`**: translated page chrome + **`admin.queries.saved.*`** labels (**mega #128**); **`admin_queries_flash`**, **`admin_queries_results_wrap`**. **`POST /admin/queries/execute`**: empty body → redirect + **`admin.queries.invalid_selection`**; non-**SELECT** / prohibited keyword custom SQL → **`admin.queries.execution_error`** with **`admin.queries.errors.*`**; saved **count** / **results** queries with stubbed **`connection.execute`**. **`Accept: text/vnd.turbo-stream.html`**: saved query → **`replace`** **`admin_queries_results_wrap`**; empty execute → **`303`** **`/admin/queries`**; bad custom SQL → stream includes escaped **`execution_error`** (**mega #179**). Unauthenticated **`GET`** → **`admin_login_path`**. |

## Admin — system monitoring

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/system_monitoring_spec.rb` | **`GET /admin/system-monitoring`**: body includes **`admin.system_monitoring.show.page_title`**, **`refresh`**, **`intro`** (**mega #129**); **`Turbo-Frame: admin_system_monitoring_main`** → layoutless **`system_monitoring_show_frame`** (omits page title; Stimulus root inside frame). Stimulus **`data-admin-system-monitoring-i18n-value`** embeds JSON from **`Admin::SystemMonitoringHelper`**. Manual refresh / no polling / no Chart CDN assertions unchanged. **`GET …/metrics.json`** shape unchanged. |

## Admin — flash toast settings

| Spec | What it proves |
|------|----------------|
| `spec/requests/admin/flash_settings_spec.rb` | **`GET /admin/settings/flash`**: full page includes **`admin.flash_settings.page_title`** + **`admin_flash_settings_flash`** + **`admin_flash_settings_form_card`**. **`Turbo-Frame: admin_flash_settings_main`** → layoutless **`flash_settings_show_frame`** (omits page title; form + test targets stay in frame). **`PATCH`** / **`POST …/test`** Turbo Streams still target **`admin_flash_settings_flash`** / **`admin_flash_settings_form_card`** (**mega #215**). Cross-map: **`systems/admin_dashboard.md`** (Flash toast settings). |

## Related maps

- `systems/plan_entitlements.md` — source of truth YAML + controller list.
- `systems/free_downgrade_alliance.md` — `FreePlanDowngradeSideEffects` + User / Stripe triggers.
- `systems/guild_role_permissions.md` — storage model + owner bypass.
- `systems/guilds_crud.md` — archive lifecycle, **`ARCHIVE_RETENTION_PERIOD`**, **`GuildArchivesController`**.
- `systems/message_center.md`, `systems/direct_messages.md`, `systems/warnings.md` — messaging + warnings; spec pointers.
- `systems/storage_files.md` — **`Storage`/`Folders`/`FileEntries`** routes and gates (**`storage_spec`**, matrix **`POST …/folders`**).
- [authorization.md](authorization.md) — layer ordering (auth → membership → Pundit → roles → plan).
- `systems/policies_pundit.md` — **`app/policies`** inventory, API **`authorize`** vs web helpers (**mega #188**).
- [discord_bot.md](discord_bot.md) — webhook ingress, **`DiscordInteractionJob`**, **`spec/requests/discord/webhooks_interactions_spec.rb`** (**mega #189**).
- `systems/admin_guild_transfer.md` — `Admin::GuildTransfersController`, audit action, Stripe gap note.
- `systems/content_moderation.md` — `Admin::ContentModerationController`, `ContentModeration::FilterService`, roadmap visibility.
- `systems/infrastructure_backup_drs.md` — PostgreSQL→S3, config snapshot tar, admin backup list, purge job.
