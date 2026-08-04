# Guild invite links

**Last updated:** 2026-04-09 (**mega #102** — **`GuildInvitesController#set_invite`** invitee scoping; **`applications_spec`** **`GET /guild_applications`** + **`GET /guild_applications/new`** **`support_center_url`** — **changelogs 293** / **303**; **`guild_member_management_spec`** **`GET …/review_applications`** — **298**; **`GET …/members/invite`** — **changelog 299**; matrix + cap docs below; API v1 endpoints added 2026-04-09)

**Model:** `GuildInviteLink`  
**Limit:** Max 10 non-expired active links per guild (`Guild#can_create_invite_link?`).  
**Route:** `POST /guilds/:id/invite_links` → `create_invite_link`. **Access:** `GuildsController#block_member_access_to_owner_features` treats **`create_invite_link`** like **`review_applications`** / **`invite_members`** — **`can_manage_applications?`** (**`applications_denied`**), not owner-only. **`guild_permissions_matrix_spec`** covers **GET** `/guilds/:id/applications` and **POST** invite links.

**Member search (invite UI):** `GET /guilds/:id/users/search` → **`search_users`** — **`can_manage_roles?`**; **403** JSON with **`roles_denied`** when denied (matches **`invite_user`**). **`guild_permissions_matrix_spec`** + **`guild_invites_spec`** (owner success paths).

**Discord `/invite`:** `DiscordInviteCommandService#process_invite` uses the same **10 usable links** cap as the web UI (`Guild#invite_links_at_capacity?`); on cap, replies with `join.invite_links_limit`.

**Alliance conflict (2026-04-05):** `JoinController#complete` rejects users who already have an active `AllianceMember` in a different alliance than the invite guild’s active `AllianceGuild`. Model validation on `AllianceMember` blocks a second active alliance. i18n: `join.conflicting_alliance`, `join.invite_links_limit`, `alliances.errors.conflicting_alliance_membership`.

**Apply-to-guild (web):** `GuildApplicationsController#create` only accepts **`guild_id`** in **`Guild.discoverable_for_applications`** (**`publicly_listed`** + **`not_archived`**), matching the member dashboard list and **`guild_applications.create.guild_not_available`** when bypassed. **`applications_spec`** (**`GET /guild_applications`** **`support_center_url`** — **changelog 293**; **`GET /guild_applications/new`** — **changelog 303**), **`guild_visibility_spec`**.

**Accept / reject / message (officers):** `set_guild_application` loads **`GuildApplication`** by id only when **`can_manage_applications?(application.guild)`**; otherwise **`my_guilds_path`** + **`controllers.guilds.access_denied`** (uniform for missing id vs wrong guild). **`applications_spec`**, **`guild_member_management_spec`**.

**Applicant invite pages (`GuildInvitesController`):** `set_invite` sets **`@invite`** from **`current_user.guild_invites`** for **`show`**, **`accept`**, and **`deny`** (no cross-user id lookup). For **`dismiss`**, if not in that association, loads by id only when **`guild.owner_id == current_user.id`** or **`can_manage_applications?(guild)`**. Otherwise **`my_guilds_path`** + **`controllers.guilds.access_denied`**. **`guild_invites_spec`**.

## API v1 endpoints

**Guild applications:** `Api::V1::GuildApplicationsController` nested under guilds.

| Method | Path | Who |
|--------|------|-----|
| `GET` | `/api/v1/guilds/:guild_id/applications` | Owner / admin (`GuildApplicationPolicy#index?`) |
| `GET` | `/api/v1/guilds/:guild_id/applications/:id` | Owner / admin **or** the applicant (`#show?`) |
| `POST` | `/api/v1/guilds/:guild_id/applications` | Any authenticated user (`#create?`) |
| `PATCH` | `/api/v1/guilds/:guild_id/applications/:id` | Owner / admin (`#update?`) — body `{ application: { status: "accepted"\|"rejected" } }` |

Accepting wraps `GuildMember` creation + `application.accepted!` in a transaction (mirrors web controller logic; Discord DM / role assignment skipped in API). `set_guild` uses `Guild.find_by` without membership restriction (applicant is not yet a member). Spec: `spec/requests/api/v1/guild_applications_spec.rb`.

**Guild invites:** `Api::V1::GuildInvitesController` — CRUD nested under guild; accept/deny top-level (invited user does not know guild_id in advance).

| Method | Path | Who |
|--------|------|-----|
| `GET` | `/api/v1/guilds/:guild_id/invites` | Owner / admin (`GuildInvitePolicy#index?`) |
| `POST` | `/api/v1/guilds/:guild_id/invites` | Owner / admin (`#create?`) — body `{ invite: { user_id: } }` |
| `DELETE` | `/api/v1/guilds/:guild_id/invites/:id` | Owner / admin (`#destroy?`) |
| `PATCH` | `/api/v1/guild_invites/:id/accept` | Invited user only (`#accept?`) |
| `PATCH` | `/api/v1/guild_invites/:id/deny` | Invited user only (`#deny?`) |

`set_invite_for_user` scopes via `GuildInvite.find_by(id:, user_id: current_user.id)` (strangers get 404). Accept transaction: creates `GuildMember` if not already a member, then `invite.update!(status: :accepted)`. Discord DM / role assignment skipped in API. Spec: `spec/requests/api/v1/guild_invites_spec.rb`.

## Related

- [guilds_crud.md](guilds_crud.md) — guild dashboard / settings context.
- [guild_role_permissions.md](guild_role_permissions.md) — **`can_manage_applications?`**, **`can_manage_roles?`**.
- [alliances.md](alliances.md) — alliance conflict on **`JoinController#complete`**.
- [policies_pundit.md](policies_pundit.md) (**mega #188**).
- [request_specs_and_gates.md](../overall/request_specs_and_gates.md) — **`guild_invites_spec`**, **`guild_permissions_matrix_spec`** rows.
