# Pundit policies

**Path:** `guildsync/app/policies/`  
**Last updated:** 2026-04-09

## Wiring

- **`ApplicationController`** includes **`Pundit::Authorization`** (`guildsync/app/controllers/application_controller.rb`).
- **Web** guild features often enforce access with **`ApplicationController`** helpers (**`can_manage_*?`**, **`plan_allows?`**, **`set_guild`**) rather than **`authorize`** on every action — see [overall/authorization.md](../overall/authorization.md) and [systems/guild_role_permissions.md](guild_role_permissions.md). **Pundit** is still the source of truth for **API v1** resources that call **`authorize`**, and for **polls** / **loot rolls** / **gear** / **games** where controllers use policies.

## Policy inventory

| Policy | Typical **`record`** | Purpose (summary) |
|--------|----------------------|-------------------|
| **`ApplicationPolicy`** | — | Default **deny** stubs; **`Scope`** base. |
| **`UserPolicy`** | **`User`** | Self **`show?`/`update?`/`guilds?`**; **`archive?`** aliases **`update?`**; optional **`user.admin?`** for cross-user read. |
| **`GuildPolicy`** | **`Guild`** | **`show?`** — **`publicly_listed?`** OR member/owner; **`update?`** / **`destroy?`** — owner/admin/owner-role; **`manage_discord?`** / **`update_discord_channels?`** — **`Guild#role_permission_enabled_for?(user, :can_manage_discord_channels)`**; **`signup_discord_event_participation?`** — owner or **active** **`GuildMember`**. |
| **`GuildMemberPolicy`** | **`GuildMember`** | **`create?`/`update?`/`destroy?`** — guild owner or member with **legacy** **`admin?`**/**`owner?`** on **`GuildMember`** (not the same as Discord slot matrix). |
| **`EventPolicy`** | **`Event`** | **`index?`** — signed-in; **`show?`/`create?`/`participate?`/`participants?`** — **`guild_member_or_owner?`**; **`update?`/`destroy?`** — creator + admin/owner member checks. |
| **`PollPolicy`** | **`Guild`** or **`Poll`** | Member **`index?`/`show?`/`vote?`**; **`new?`/`create?`/`post_to_discord?`/`destroy?`** — owner or **`can_manage_polls?`** (four **`permission_role_*`** slots + flags). |
| **`LootRollPolicy`** | **`Guild`** or **`LootRoll`** | Member **`index?`/`show?`**; manage actions use **`can_manage_guild_settings?(guild)`** via **`member.role`** string (**`role_1`**…**`role_4`**) + **`role_*_can_manage_guild_settings`** — differs from slot-ID style in **`PollPolicy`**. |
| **`GearPolicy`** | **`Guild`** | Member **`index?`/`show?`/`upload?`**; **`request_update?`/`request_bulk?`** — owner or slot **`role_*_can_manage_gear_requests?`**. **`Scope`** — guilds with active membership. |
| **`GuildApplicationPolicy`** | **`GuildApplication`** | **`index?`/`update?`** — owner or `GuildMember` with `admin?`/`owner?` role; **`show?`** — same OR `record.user == user`; **`create?`** — any authenticated user (applicant is not yet a member). |
| **`GuildInvitePolicy`** | **`GuildInvite`** | **`index?`/`create?`/`destroy?`** — owner or admin/owner-role member; **`accept?`/`deny?`** — `record.user == user` (invited user only). |
| **`GamePolicy`** | **`Game`** | **`ADMIN_EMAILS`** / **`ADMIN_USER_IDS`** env allow-list only. **`Scope`** — all or none. |

## API-focused behaviour (detail)

**`UserPolicy`:** **`Api::V1::UsersController#set_user`** enforces **`show?`/`update?`/`guilds?`/`archive?`** before actions; failures → **404** JSON **`controllers.guilds.access_denied`**. **`POST …/archive`** success → **`api.users.account_archived`**. **`users_spec`**, **`user_policy_spec`**.

**`GuildPolicy`:** **`Api::V1::GuildsController#set_guild`** uses **`show?`** for public **`GET`** guild **show**; **`update?`/`destroy?`** after scoped load. **`manage_discord?`**/**`update_discord_channels?`** align with **`Guild#role_permission_enabled_for?`** (**`discord_spec`**, **`guild_policy_spec`**). **`signup_discord_event_participation?`** — **`Api::V1::DiscordController#signup_event`**.

**`Api::V1::GuildMembersController`:** **`set_guild`** membership / ownership only; **`authorize_guild_access`** — active member or owner (**404** **`access_denied`**, **mega #111**). **`set_guild_member`** — **`find_by(id:)`** (**mega #110**, **`guild_members_spec`**). **`show`** added (no separate `authorize` call — `authorize_guild_access` before-action covers it, consistent with `index`).

**`Api::V1::GuildApplicationsController`:** **`set_guild`** uses bare `Guild.find_by` (applicant is not a member yet); Pundit `GuildApplicationPolicy` gates each action. Accept path wraps member creation + status update in a transaction. Spec: **`guild_applications_spec`**.

**`Api::V1::GuildInvitesController`:** CRUD nested under guild uses `GuildInvitePolicy`; `accept`/`deny` are top-level (no `guild_id`) with `set_invite_for_user` scoping by `user_id` before `authorize`. Spec: **`guild_invites_spec`**.

**`EventPolicy`** extended: `unparticipate` action reuses `participate?` check (same guild-member-or-owner guard). `DELETE /api/v1/events/:id/participate` → `EventsController#unparticipate`; returns **404** `api.v1.not_participating` when no record found.

**`Api::V1::DiscordController`:** **`resolve_guild_for_discord_api`** + **`authorize`**; JSON **`api.discord.*`** (**mega #114**). **`discord_spec`**.

**`EventPolicy`:** **`Api::V1::EventsController#set_event`** — **`Event.find_by`** + **`show?`** for top-level **`/api/v1/events/:id`** (**404** **`access_denied`**). **`events_spec`**.

**`Api::V1::BaseController`:** **`Pundit::NotAuthorizedError`** → **403** **`api.v1.not_authorized`**; auth failures **`api.v1.authentication_required`**; **`RecordNotFound`** → **`api.v1.resource_not_found`** (**mega #112**).

**`Api::V1::AuthController`:** Skips Devise **`authenticate_user!`** for **`sign_up`/`sign_in`/`me`/`sign_out`**; **`api.auth.*`** (**mega #113**). **`auth_spec`**.

## Plan entitlements

Policies generally do **not** duplicate **`plan_allows?`** — **controllers** layer plan gates (e.g. storage, message center) before or alongside Pundit. See [systems/plan_entitlements.md](plan_entitlements.md).

## Specs (high level)

- **`spec/policies/*_spec.rb`** — policy unit tests where present.
- **`spec/requests/api/v1/*_spec.rb`** — integration for **`authorize`** + JSON i18n.
- **`spec/requests/guild_permissions_matrix_spec.rb`** — web permission matrix (helpers + **`plan_entitlements`**, not always Pundit).

**Related:** [overall/authorization.md](../overall/authorization.md), [systems/guild_role_permissions.md](guild_role_permissions.md), [overall/request_specs_and_gates.md](../overall/request_specs_and_gates.md).
