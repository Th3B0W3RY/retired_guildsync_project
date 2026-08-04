# Message center

**Last updated:** 2026-04-06 (**mega #182**, **Lane C**; **`message_center_isolation_spec`** **`GET /guilds/:id/message_center`** **`support_center_url`** — **changelog 284**)

**Controller:** `guildsync/app/controllers/message_center_controller.rb`  
**Concern:** `RequiresActiveGuildAccess` — archived guilds redirect before message-center logic.

## Routes (guild id = **`params[:id]`**)

| Method | Path | Action |
|--------|------|--------|
| GET | `/guilds/:id/message_center` | `index` |
| GET | `/guilds/:id/message_center/search_recipients` | `search_recipients` (JSON) |
| GET | `/guilds/:id/message_center/conversation/:recipient_id` | `conversation` (JSON) |
| POST | `/guilds/:id/message_center/send` | `create` (JSON) |

## `before_action` order

1. **`authenticate_user!`**
2. **`set_guild`** — membership / ownership resolution only (no `Guild.find` for strangers):
   - `current_user.guilds.find_by(id: params[:id])` → else `owned_guilds` → else `Guild.find_by(id:, owner_id: current_user.id)`;
   - miss → **`my_guilds_path`** + **`controllers.guilds.access_denied`**
3. **`require_active_guild_access`** (archived-only behavior from concern)
4. **`ensure_guild_member`** — must be in **`@guild.members`** and **`can_use_message_center?(@guild)`**; else **`guild_path(@guild)`** + **`message_center.access_denied`**
5. **`require_message_center_plan!`** — **`plan_allows?(:message_center)`** or **`upgrade_pricing_path`** + **`plan_entitlements.upgrade_required`**

## Behaviour notes

- **`search_recipients`** — guild members (+ optional other-guild **owners** when current user owns **`@guild`**); ILIKE on username/email; JSON list.
- **`conversation`** / **`create`** — **`can_message?`**: not self; same-guild member **or** owner-to-owner (recipient has **`owned_guilds`**). Invalid recipient → **422** JSON **`message_center.invalid_recipient`**. **`create`**: blank content → **`message_center.content_blank`**.
- **`conversation` query** — `DirectMessage.between(...).where("guild_id IS NULL OR guild_id = ?", @guild.id)` so other-guild rows do not leak into this guild’s thread.
- **`guild_id_for_conversation`** — `guild_id` = **`@guild.id`** when recipient is a member; else **`nil`** (owner-to-owner).
- **Discord DM** — after save, **`deliver_message_center_dm`** best-effort via **`DiscordService#send_dm`**; timeouts/API errors logged (**`GuildsyncLoggers.discord_failures`**) without failing the HTTP create.

## Specs

- **`spec/requests/message_center_isolation_spec.rb`** — **`GET …/message_center`** — **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 284**); non-member, slot denial, invalid recipient on **send** and **`GET …/conversation`**, guild-scoped conversation, **`guild_id`** on create.
- **`spec/requests/plan_entitlements_matrix_spec.rb`** — plan tier vs message center.
- **`spec/requests/activity_feed_spec.rb`** — stranger export (shared **`set_guild`** pattern with activity feed).

**Persistence / model:** [direct_messages.md](direct_messages.md) (**mega #184**).

## Related

- [plan_entitlements.md](plan_entitlements.md) — **`:message_center`**.
- [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**).
- [activity_feed.md](activity_feed.md) — same **`set_guild`** resolution pattern (**mega #96** alignment in specs).
- [warnings.md](warnings.md) (**mega #180**) — parallel plan-gated guild feature.
- [authorization.md](../overall/authorization.md) (**mega #211**).
- [request_specs_and_gates.md](../overall/request_specs_and_gates.md).
