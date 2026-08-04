# Guild documents

**Last updated:** 2026-04-06 (map; **mega #119** — **`#autosave`** JSON **`api.v1.not_authorized`** when edit not allowed; **`guild_documents_spec`** index **`support_center_url`** — **changelog 287**; **`GET …/documents/new`** — **changelog 309**; **`GET …/documents/:id`** — **changelog 310**; **`GET …/documents/:id/edit`** — **changelog 311**)

**Controller:** `GuildDocumentsController`  
**Plan gate:** `require_guild_documents_plan!` → `plan_allows?(:guild_documents)` (skipped for **`share`** only).  
**Archived guilds:** `RequiresActiveGuildAccess` — **`require_active_guild_access`** redirects archived guilds to **`guild_archives_path`**.

## Guild resolution (`set_guild`)

**`@guild = Guild.find(params[:guild_id])`** is **intentional**, unlike most guild-scoped controllers that resolve via **`current_user.guilds`** / **`owned_guilds`**. Reasons:

- **`index`** is meant to let a **subscribed** user open **another** guild’s documents URL and see only documents they **`can_view?`** (e.g. **public** docs), while managers see the full list when **`can_manage_documents?`**.
- **`show`**, **`edit`**, **`update`**, **`destroy`**, **`autosave`**, **`upload_image`**, folders, etc. still enforce **`check_permissions`** / **`check_view_permissions`** / **`can_manage_documents?`** as appropriate.
- **`share`** skips auth; **`check_share_permissions`** validates slug + visibility (private requires auth + **`@guild.members`**).

**Security note:** Do not “fix” **`set_guild`** to membership-only **`find_by`** without revisiting **index** product rules and **`guild_documents_spec`**.

**Tests:** `spec/requests/guild_documents_spec.rb` — **`GET …/documents`** — **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 287**); **`GET …/documents/new`** — same matrix (**changelog 309**); **`GET …/documents/:id`** — same matrix (**changelog 310**); **`GET …/documents/:id/edit`** — same matrix (**changelog 311**); **`POST …/autosave`** with existing **`id`**: user without **`can_edit?`** (e.g. officer with **`can_manage_documents?`** only) → **403** JSON **`api.v1.not_authorized`** (**mega #119**).

## Related

- [plan_entitlements.md](plan_entitlements.md) — **`:guild_documents`** tier gate (**`plan_allows?`**).
- [storage_files.md](storage_files.md) — sibling **`:file_storage`** surface (different controller stack).
- [authorization.md](../overall/authorization.md) (**mega #211**) — Pundit / **`can_manage_documents?`** vs **`can_edit?`**.
- [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**) — sidebar entry visibility.
- [request_specs_and_gates.md](../overall/request_specs_and_gates.md) — **`guild_documents_spec`** and matrix rows.
