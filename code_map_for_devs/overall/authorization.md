# Authorization

**Last updated:** 2026-04-02 (mega **#211** — layer order, **`RequiresActiveGuildAccess`**, Pundit vs **`can_manage_*?`**, API vs HTML)

This page describes **how access control composes** across the stack. For a **policy-by-policy and controller inventory**, see **[systems/policies_pundit.md](../systems/policies_pundit.md)** (**mega #188**). For auth/MFA **before** guild logic, see **[authentication_mfa.md](authentication_mfa.md)** and **[request_lifecycle.md](request_lifecycle.md)**.

## Layers (typical order for guild-scoped web actions)

| # | Layer | What it enforces |
|---|--------|------------------|
| 1 | **Session + MFA** | **`ApplicationController`**: signed-in user, MFA session flags where required — see **[request_lifecycle.md](request_lifecycle.md)**. |
| 2 | **Resolve `Guild` (`set_guild`)** | Load **`@guild`** from **`params[:guild_id]`** / **`params[:id]`** in a way that avoids IDOR (often: only guilds the user **owns** or **is a member of**; strangers get redirect/404). **Pattern varies by controller** — compare **`PollsController#set_guild`** vs **`GuildsController`**. |
| 3 | **`RequiresActiveGuildAccess`** | **Only** blocks use of **archived** guilds: if **`@guild.archived?`**, redirect to **`guild_archives_path`** with **`guild_archives.alerts.archived_unavailable`**. **File:** `guildsync/app/controllers/concerns/requires_active_guild_access.rb`. It does **not** replace membership checks. |
| 4 | **Membership** | Many controllers define **`ensure_guild_member`** (or equivalent): user must be **`@guild.members`** or **`@guild.owner`**. |
| 5 | **Pundit** | **`include Pundit::Authorization`** on **`ApplicationController`**. Controllers call **`authorize record, :action?`**. **`ApplicationPolicy`** is **deny-by-default** (`index?`/`show?`/… **`false`** until overridden). |
| 6 | **Discord-linked role flags on `Guild`** | **`Guild#role_permission_enabled_for?(user, :suffix)`** and **`ApplicationController#can_manage_*?(guild)`** helpers (owner wins; non-owner needs matching **`permission_role_*_id`** + boolean flags). Used in policies and in some **custom** `before_action` gates (e.g. **`authorize_create`** on polls). |
| 7 | **Plan entitlements** | **`current_user.plan_allows?(:feature)`** (**`PlanEntitlementService`** + **`config/plan_entitlements.yml`**). **Orthogonal** to guild roles: both may apply (e.g. feature visible only on paid tier **and** only for members with permission). |

## Pundit: HTML vs JSON API

- **HTML / Turbo:** Unauthorized **`authorize`** raises **`Pundit::NotAuthorizedError`** (default Rails handling / flash; i18n key **`pundit.not_authorized`** in locale files).
- **API v1:** **`Api::V1::BaseController`** **`rescue_from Pundit::NotAuthorizedError`** → JSON (**e.g.** **`api.v1.not_authorized`**) — see **`policies_pundit.md`** and API specs.

## Hybrid controllers (Pundit + custom redirects)

Not every gate goes through **`authorize`**. Some actions use **`can_manage_*?`** with explicit **`redirect_to`** + flash (clearer UX for “you’re a member but not allowed”). **`PollsController`** is an example: **`authorize @guild, :show?`** on **`index`**, plus **`authorize_create`** / **`authorize_destroy`** wrappers around **`can_manage_polls?`**. When adding features, **match the surrounding controller** and extend **`policies_pundit.md`** if you introduce a new policy.

## Guild policy vs record policies

- **`GuildPolicy`** — high-level **`show?`** / **`update?`** / Discord signup participation, etc.; **`show?`** allows **publicly listed** guilds for guests, else active **member** or **owner**.
- **Resource policies** (**`PollPolicy`**, **`EventPolicy`**, **`GearPolicy`**, …) — per-model rules; many delegate to **`role_permission_enabled_for?`** or **`GuildMember`** role enums.

## Admin routes

**`admin_user?`** and **`Admin::*`** controllers are a **separate** surface (no guild **`set_guild`**). Do not mix admin checks into guild policies.

## Alliance routes

**`AllianceNestedAccess`** and alliance controllers add **`alliance_id`** scoping — see **[systems/alliances.md](../systems/alliances.md)** and **[data_model_core.md](data_model_core.md)**. Same idea: resolve record → membership/access → policy.

## Deny-by-default and IDOR

- **Deny-by-default:** nil/false permission flags mean **no** for non-owners; **never** rely only on hiding UI.
- **IDOR:** as another user, hit **`…/guilds/:id/…`** for a guild you do not belong to → **must** fail (redirect, **404**, or **403** JSON). **`request_specs_and_gates.md`** tables list high-signal specs.

## Spec pointers

| Area | Where |
|------|--------|
| Policy unit tests | **`spec/policies/**`** |
| HTTP + gates | **`spec/requests/*_spec.rb`**, **`spec/requests/guild_permissions_matrix_spec.rb`** (**Lane A** — coordinate before large edits) |
| Consolidated tables | **[request_specs_and_gates.md](request_specs_and_gates.md)** |

**Related:** [systems/guild_role_permissions.md](../systems/guild_role_permissions.md), [systems/policies_pundit.md](../systems/policies_pundit.md), [systems/plan_entitlements.md](../systems/plan_entitlements.md), [data_model_core.md](data_model_core.md).
