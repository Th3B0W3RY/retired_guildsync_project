# Member leaderboard

**Last updated:** 2026-04-06 (**`leaderboard_spec`** **`GET /leaderboard`** **`support_center_url`** — **changelog 281**, **Lane C**; controller + service — mega #198)

**Purpose:** Signed-in, **cross-guild** weighted scoreboard for event attendance, poll votes, and closed loot-roll entries. Distinct from Discord **`/leaderboard`** (per-guild signup ranking).

## Route & controller

| Item | Detail |
|------|--------|
| Route | **`GET /leaderboard`** → **`leaderboard_path`** → **`LeaderboardController#index`** |
| Auth | **`before_action :authenticate_user!`** only (no per-guild Pundit on this action). |
| Scope | **`current_user.guilds.pluck(:id)`** — any guild membership counts; **no** rows from guilds the user does not belong to. |
| Empty | No guild ids → **`@leaderboard_data = []`** without calling the service. |
| Session | **`#preserve_session`** mirrors MFA-related session keys (same pattern as some other member pages) so session state stays coherent after navigation. |

**Views:** `app/views/leaderboard/index.html.erb` and `index.html+mobile.erb`. Empty copy includes **`No participation data available yet`** when there is nothing to show.

## Service: `Guilds::MemberLeaderboardScores`

**Entry:** **`Guilds::MemberLeaderboardScores.call(user_guild_ids:)`** — dedupes integer guild ids, returns an **Array** of hashes sorted by score descending.

**Identity + server grouping:** Each row key is **`[ [:discord \| :user, id_string], server_label ]`** so the same Discord user on two servers appears twice. **`server_label`** = **`guild.guild_discord_setting.discord_guild_name`** if present, else **`guild.name`**.

**Payload shape (per row):** `discord_username`, `discord_server_name`, `score`, `participation_count` — today **`participation_count` equals `score`** (weighted points, not a raw event count).

## Scoring (weighted)

Constants on the service:

| Source | Weight | Query notes |
|--------|--------|-------------|
| **`DiscordEventParticipation`** (`on_time: true`) | **10** / row | Joins **`events`** with **`status` in `in_progress`, `completed`** only — **`scheduled`** (and other statuses) **excluded**. |
| **`PollVote`** | **10** / vote | Guild polls only; **`discord_user_id`** path vs **`user_id`** path for poll-only web voters. |
| **`LootRollEntry`** (`is_reroll: false`) | **1** / entry | Parent **`LootRoll`** **`status`** must be **`closed`**. |

## Discord slash command (different formula)

**`/leaderboard`** uses **`DiscordLeaderboardCommandService`** — ranks by **`DiscordEventSignup`** (on-time) **per a single guild**. It does **not** use **`MemberLeaderboardScores`**. Product parity between Discord and web is **not** guaranteed until explicitly aligned.

## Specs

- **`spec/requests/leaderboard_spec.rb`** — signed-in **`GET /leaderboard`**: empty / non-on-time / scheduled events excluded; weighted totals; sort order; fallback server name without **`GuildDiscordSetting`**; multiple guilds; isolation (**no** other users’ guilds); **`support_center_url`** in member chrome (default + custom, desktop + **`:mobile`**) — **changelog 281**.
- **`spec/services/guilds/member_leaderboard_scores_spec.rb`** — service unit behavior.

**Related:** **`overall/discord_bot.md`** (gateway commands), **`systems/guilds_crud.md`** (guild context). This page is **not** behind **`plan_entitlements.yml`** matrix checks beyond **`authenticate_user!`**.
