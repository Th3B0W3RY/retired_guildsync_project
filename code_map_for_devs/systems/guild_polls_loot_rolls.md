# Guild polls & loot rolls (web)

**Last updated:** 2026-04-06 (**mega #210**, Lane C — developer map; **`polls_spec`** / **`loot_rolls_spec`** **`GET …/polls/new`** + **`GET …/loot_rolls/new`** **`support_center_url`** — **changelog 308**; show **`:id`** — **307**; **`loot_rolls_spec`** index — **290**; **`polls_spec`** index — **289**; alliance **`alliance_loot_rolls_spec`** **`GET …/alliance_loot_rolls`** — **317**; **`GET …/alliance_loot_rolls/:id`** — **318** — see [`alliances.md`](alliances.md))

Guild-scoped **`Poll`** and **`LootRoll`** UIs under **`/guilds/:guild_id/polls`** and **`/guilds/:guild_id/loot_rolls`**. Alliance-scoped counterparts live under **`/alliances/:alliance_id/…`** — see [`alliances.md`](alliances.md).

## Routes

Nested under guild `resources` in `config/routes.rb`:

| Verb / path | Controller#action |
|-------------|-------------------|
| `GET …/polls` | `PollsController#index` |
| `GET …/polls/new`, `POST …/polls` | `#new`, `#create` |
| `GET …/polls/:id` | `#show` |
| `POST …/polls/:id/vote` | `#vote` (JSON) |
| `POST …/polls/:id/post_to_discord` | `#post_to_discord` |
| `DELETE …/polls/:id` | `#destroy` |
| `GET …/loot_rolls` | `LootRollsController#index` |
| `GET …/loot_rolls/new`, `POST …/loot_rolls` | `#new`, `#create` |
| `GET …/loot_rolls/:id` | `#show` |
| `POST …/loot_rolls/:id/close`, `…/force_reroll` | `#close`, `#force_reroll` |
| `DELETE …/loot_rolls/:id` | `#destroy` |

Named helpers follow Rails conventions (`guild_polls_path`, `guild_poll_path`, `vote_guild_poll_path`, `guild_loot_rolls_path`, `close_guild_loot_roll_path`, etc.).

## Controller stack

Both controllers include **`RequiresActiveGuildAccess`** and run:

`authenticate_user!` → `require_mfa_if_enabled` → `set_guild` → `require_active_guild_access` → `ensure_guild_member`

Then Pundit via **`authorize`** / **`authorize_create`** / **`authorize_manage`** / **`authorize_destroy`** on the relevant actions.

## Policies (contrast)

- **`PollPolicy`**: create/post/destroy use **`can_manage_polls?(guild)`** — **Discord role id** slots (`permission_role_*_id` + **`role_*_can_manage_polls`**). Vote/show are any active member or owner.
- **`LootRollPolicy`**: create/close/reroll/destroy use **`can_manage_guild_settings?(guild)`** — **`GuildMember#role`** string (`owner`, `role_1`…`role_4`) + **`role_*_can_manage_guild_settings`**. See [`policies_pundit.md`](policies_pundit.md).

## Discord integration

- **Polls:** optional auto-post when **`GuildDiscordSetting`** is connected and **`polls_channel_id`** is set; **`DiscordPollService`** posts/updates messages. **`PollsController#vote`** may call **`update_poll_message`** then **`broadcast_poll_update`**.
- **Loot rolls:** **`loot_rolls_channel_configured?`** is required to **`create`**; **`DiscordLootRollService`** posts and updates the Discord message. **`#close`** / **`#force_reroll`** update Discord and call **`LootRollsChannel.broadcast_update`** via **`broadcast_loot_roll_update`**.

## Action Cable

- **`PollsChannel`**: params **`poll_id`**; **`find_by`** + guild membership check; **`stream_for poll`**. Server sends **`{ type: 'vote_update', vote_counts, vote_percentages, total_votes }`** from **`PollsController#broadcast_poll_update`**. **`DiscordInteractionJob`** also **`broadcast_to`** the poll for Discord-origin votes.
- **`LootRollsChannel`**: params **`loot_roll_id`**; same membership pattern; **`LootRollsChannel.broadcast_update(loot_roll)`** builds a single **`loot_roll_update`** payload (**`entries`**, **`winner_id`**, **`has_tie`**, **`currently_open`**, anonymous **`"Anonymous"`** display names) for web, **`DiscordInteractionJob`**, bot, and deadline job (**mega #155**, **#156**).

Subscription hardening (**reject** + **`return`**) matches **`polls_channel_spec`** / **`loot_rolls_channel_spec`** (**mega #153**).

## Stimulus (web show pages)

- **`poll_vote_controller`** (**`poll-vote`**): **`pollId`**, **`voteUrl`** values; subscribes to **`PollsChannel`**; **`POST`** JSON to **`voteUrl`** with CSRF (**mega #150**, **#158**).
- **`loot_roll_controller`** (**`loot-roll`**): **`lootRollId`**, **`canManage`**, **`forceRerollUrl`**, **`labels`** (pluralized roll-count strings); subscribes to **`LootRollsChannel`**; applies **`loot_roll_update`** to DOM targets (**mega #156**).

Both use **`getCableConsumer()`** from **`app/javascript/cable_consumer.js`** (**mega #159**).

## Request / channel specs

| Area | Spec |
|------|------|
| HTTP + markup | `spec/requests/polls_spec.rb` (index **289**; **new** — **308**; show **`:id`** — **307**), `spec/requests/loot_rolls_spec.rb` (index **290**; **new** — **308**; show **`:id`** — **307**) |
| Auto-close past deadline | `spec/jobs/loot_roll_deadline_job_spec.rb` — **`LootRollDeadlineJob`** (not scheduled in **`sidekiq.rb`** by default; see [`background_jobs.md`](../overall/background_jobs.md) **mega #212**) |
| Cable | `spec/channels/polls_channel_spec.rb`, `spec/channels/loot_rolls_channel_spec.rb` |
| Permission matrix | `spec/requests/guild_permissions_matrix_spec.rb` — **`new_guild_poll_path`**, **`new_guild_loot_roll_path`** (**mega #72**) |

## Related maps

- [`sidebar_navigation.md`](sidebar_navigation.md) — guild submenu entries for polls / loot rolls (**mega #219**).
- [`alliances.md`](alliances.md) — **`AlliancePollsController`**, **`AllianceLootRollsController`**, alliance Cable channels.
- [`guild_role_permissions.md`](guild_role_permissions.md) — role flags vs plan gates.
- [`overall/request_specs_and_gates.md`](../overall/request_specs_and_gates.md) — tables for guild polls, loot rolls, and Cable.
- [`overall/background_jobs.md`](../overall/background_jobs.md) — **`LootRollDeadlineJob`** (auto-close past **`deadline_at`** + **`LootRollsChannel`**) is **not** enqueued from **`sidekiq.rb`**; operators must schedule (**mega #212**).
