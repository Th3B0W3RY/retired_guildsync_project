# Discord bot integration

**Last updated:** 2026-04-06 (mega **#189** — Lane C map; **`events_bot_integration_spec`** **`GET …/discord_events/:id`** **`support_center_url`** — **changelog 305**; **`GET …/discord_events/new`** **`support_center_url`** — **changelog 304**; **`connections_spec`** **`GET …/discord/connect`** **`support_center_url`** — **changelog 300**; gateway + HTTP interactions + job deferral)

## Runtime modes

| Mode | Role |
|------|------|
| **Gateway bot** | **`DiscordBotService`** (`app/services/discord_bot_service.rb`) — **`discordrb`** WebSocket when **`ENV["DISCORD_BOT_TOKEN"]`** is set; registers slash/button handlers in-process. |
| **HTTP interactions** | Discord → **`POST /discord/webhooks`** (`DiscordWebhooksController#interactions`) or **`POST /discord/interactions`** (`DiscordController#interactions`). Signature verification (**Ed25519**), immediate **PING** / **deferred** ack, heavy work via **`DiscordInteractionJob`**. |

Production may use one or both depending on deployment; keep behaviour aligned when changing interaction **`custom_id`** conventions.

## Environment

- **`DISCORD_BOT_TOKEN`** — bot login (gateway + REST as configured).
- **`DISCORD_PUBLIC_KEY`** — used by **`DiscordWebhooksController`** for **`X-Signature-Ed25519`** verification.
- Optional: webhook URLs for error notify (**`overall/error_observability.md`**).

## HTTP ingress (webhooks)

**`DiscordWebhooksController`** (`skip_before_action` CSRF + Devise):

- Reads **`request.raw_post`** for signature verification (avoid buffering issues vs Discord’s **3s** window).
- Invalid signature → **200** JSON ephemeral **`discord.webhooks.invalid_signature`** (**flags: 64**).
- **`type` 1** (PING) → **`{ type: 1 }`** immediately.
- **`type` 2** application commands, **`3`** message components, **`5`** modals → deferred response then **`DiscordInteractionJob.perform_now`/`perform_later`** with payload (see controller tail for branching).

**Specs:** `spec/requests/discord/webhooks_interactions_spec.rb` (signature, PING, job dispatch for poll/loot patterns).

## Gateway service (high level)

**`DiscordBotService`** — builds **`discordrb` `Bot`**, intent list (**`servers`**, **`server_messages`**, reactions, **`server_members`**), macOS **`SSL_CERT_FILE`** workaround. Command/button routing delegates to focused services (below). Alliance poll / loot roll paths may call **`AlliancePollsChannel.broadcast_vote_update`** / **`AllianceLootRollsChannel.broadcast_update`**; failures are logged and should not block Discord follow-ups (**mega #154** / **#157**).

## REST / DMs

**`DiscordService`** (`discord_service.rb`) — HTTP helpers used by web UI (e.g. Message Center DM), jobs, and some webhook follow-ups. **`DiscordApi`** / **`discord_api.rb`** — lower-level client concerns.

## Service index (`app/services/discord_*.rb`)

| Area | Examples |
|------|----------|
| **Commands** | **`DiscordApplicationCommandService`**, **`DiscordGuildCommandService`**, **`DiscordHelpCommandService`**, **`DiscordMemberCommandService`**, **`DiscordPollCommandService`**, **`DiscordLootCommandService`**, **`DiscordEventCommandService`**, **`DiscordDocsCommandService`**, **`DiscordActivityCommandService`**, **`DiscordProfileCommandService`**, **`DiscordInviteCommandService`**, **`DiscordLeaderboardCommandService`**, **`DiscordAllianceCommandService`**, … |
| **Interactions / features** | **`DiscordPollService`**, **`DiscordLootRollService`**, **`DiscordGearService`**, **`DiscordReactRolesService`**, **`DiscordAlliancePollService`**, **`DiscordAllianceLootRollService`** |
| **OAuth** | **`DiscordUserOAuthService`** |
| **Shared** | **`DiscordCommandHelpers`**, **`DiscordGuildMemberLabel`**, **`DiscordTokenExpiredError`** |

## Web OAuth & guild linking

- **User login:** **`DiscordUserAuthController`** — routes under **`/auth/discord`** (`routes.rb`).
- **Guild connection:** **`DiscordConnectionsController`** — **`guild_connect_discord_path`** (`GET /guilds/:id/discord/connect`), OAuth callback, server select/connect; gated by **`can_manage_discord_channels?`** (see **`systems/guild_role_permissions.md`**, **`policies_pundit.md`**). Member chrome **`support_center_url`** — **`spec/requests/discord/connections_spec.rb`** **changelog 300**.

## API v1 Discord (member app)

**`Api::V1::DiscordController`** — **`GET/PATCH …/discord/channels`**, **`POST …/discord/events/:id/signup`**. JSON **`api.discord.*`** (**mega #114**). **`spec/requests/api/v1/discord_spec.rb`**.

## Per-guild settings

**`GuildDiscordSetting`** — channel IDs for events, gear, etc.; edited via **`GuildsController#update_discord_channels`** and API above.

## i18n (webhooks)

**`discord.webhooks.*`** — ephemeral responses, RSVP / alliance RSVP / event embed / legacy event details (**10** locales). **`discord_event_signups#webhook`** uses **`controllers.discord_event_signups.webhook.*`** (**mega #119**).

## Jobs

- **`DiscordInteractionJob`** — background processing for deferred interactions; alliance poll Cable rescue logged (**job**).
- Gear / warnings / other features enqueue domain jobs (**`DiscordGearService`**, **`GuildWarningDiscordDmJob`**, etc.).

**Related:** [systems/ocr_ai_gear.md](../systems/ocr_ai_gear.md) (Discord gear OCR), [systems/warnings.md](../systems/warnings.md) (warning DMs), [systems/policies_pundit.md](../systems/policies_pundit.md) (API **`GuildPolicy`**), [overall/error_observability.md](error_observability.md), [overall/request_specs_and_gates.md](request_specs_and_gates.md).
