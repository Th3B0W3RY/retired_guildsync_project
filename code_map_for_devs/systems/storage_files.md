# Guild file storage

**Last updated:** 2026-04-06 (**mega #186**, **Lane C**; **`storage_spec`** **`GET …/storage`** **`support_center_url`** — **changelog 286**)

## Scope

Guild-scoped **folders** and **file entries** (Active Storage blobs). HTML shell: **`StorageController#show`**. Mutations and JSON: **`FoldersController`**, **`FileEntriesController`**.

**S3 / service config:** [overall/storage_s3.md](../overall/storage_s3.md).

## Routes (`params[:guild_id]`)

| Method | Path | Controller#action | Named helper (typical) |
|--------|------|-------------------|-------------------------|
| GET | `/guilds/:guild_id/storage` | **`storage#show`** | **`guild_storage_path(guild)`** |
| POST | `/guilds/:guild_id/file_entries` | **`file_entries#create`** | **`guild_file_entries_path(guild)`** |
| PATCH | `/guilds/:guild_id/file_entries/bulk_move` | **`file_entries#bulk_move`** | **`bulk_move_guild_file_entries_path(guild)`** |
| DELETE | `/guilds/:guild_id/file_entries/bulk_destroy` | **`file_entries#bulk_destroy`** | **`bulk_destroy_guild_file_entries_path(guild)`** |
| GET | `/guilds/:guild_id/file_entries/:id/download` | **`file_entries#download`** | **`download_guild_file_entry_path(guild, id)`** |
| DELETE | `/guilds/:guild_id/file_entries/:id` | **`file_entries#destroy`** | **`guild_file_entry_path(guild, id)`** |
| POST | `/guilds/:guild_id/folders` | **`folders#create`** | **`guild_folders_path(guild)`** |
| PATCH | `/guilds/:guild_id/folders/:id` | **`folders#update`** | **`update_guild_folder_path(guild, id)`** |
| DELETE | `/guilds/:guild_id/folders/:id` | **`folders#destroy`** | **`guild_folder_path(guild, id)`** |

## Guild resolution (`set_guild`)

**`FoldersController`** and **`FileEntriesController`** (not **`StorageController`** text): if no guild via **`current_user.guilds`** / **`owned_guilds`** / **owner fallback** → JSON requests get **404** + **`error`** = **`controllers.guilds.access_denied`**; HTML → **`my_guilds_path`** + flash.

**`StorageController#set_guild`**: same membership resolution; failure → **`my_guilds_path`** + **`access_denied`** (HTML storage page).

## `before_action` order (conceptual)

### `StorageController`

1. **`authenticate_user!`**
2. **`ensure_mfa_session_flags`** — Discord auth sets MFA session flags; password+MFA refreshes **`mfa_verified_at`** window
3. **`set_guild`**
4. **`require_active_guild_access`** (**`RequiresActiveGuildAccess`**)
5. **`require_file_storage_plan!`** — **`plan_allows?(:file_storage)`**; else **`upgrade_pricing_path`** + **`plan_entitlements.upgrade_required`**
6. **`ensure_guild_member`** — member or owner; else **`root_path`** + **`controllers.storage.not_member`**

### `FoldersController`

1. **`authenticate_user!`** → **`ensure_mfa_session_flags`** → **`set_guild`** → **`require_active_guild_access`**
2. **`check_permissions`** — **`can_manage_files?(@guild)`**; else **`guild_storage_path`** + **`controllers.folders.manage_denied`**
3. **`set_folder`** (show/update/destroy only)
4. **`create`** forces **JSON** format (**`force_json_format`**)

### `FileEntriesController`

1. **`authenticate_user!`** → **`ensure_mfa_session_flags`** → **`set_guild`** → **`require_active_guild_access`**
2. **`ensure_guild_member`** — same idea as storage (**`not_member`**)
3. **`check_permissions`** — **`except: [:show, :download]`** — mutating actions need **`can_manage_files?`**
4. **`set_file_entry`** where applicable

**Download / read:** **`download`** re-checks membership/owner, then **`rails_blob_path`** attachment.

**Plan note:** **`require_file_storage_plan!`** lives on **`StorageController`** only. **`FoldersController`** / **`FileEntriesController`** do **not** call **`plan_allows?(:file_storage)`**; in practice the UI is reached after **`GET …/storage`**, and **`storage_spec`** / matrix specs document expected behaviour. If hardening JSON endpoints for direct calls matters, add an explicit plan check in a dedicated change (coordinate with **Lane A** matrix if extending specs).

## Behaviour notes

- **`FoldersController#create`** — **`ParameterMissing`** → **400** JSON **`controllers.folders.missing_required_parameter`**; other exceptions → **422** **`controllers.folders.unexpected_create_error`** (**mega #118**, **10** locales).
- **`FoldersController#update`** — blocks moving a folder into itself or a descendant (**`cannot_move_into_self`**).
- **`FoldersController#destroy`** — rejects non-empty folder (**`not_empty`**).
- **`FileEntriesController#create`** — multi-file **`params[:files]`**; optional **`folder_id`** scoped to **`@guild.folders`**.
- **Bulk** move/destroy — IDs scoped to **`@guild.file_entries`**.

## Failure / abuse modes

- Wrong **`guild_id`** / not a member → **`access_denied`** (JSON **404** + **`error`** on folder/file controllers) or storage redirect.
- **Free / plan without `file_storage`** → upgrade path from **`StorageController`**.
- **Member without `can_manage_files?`** → **`guild_storage_path`** + manage-denied flash (folders/file mutations).

## Specs

- **`spec/requests/storage_spec.rb`** — plan + membership; stranger **`GET …/storage`**; **`support_center_url`** in member chrome on **`GET …/storage`** (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 286**).
- **`spec/requests/guild_permissions_matrix_spec.rb`** — **`POST …/folders`** JSON vs **`role_1_can_manage_files`** (**Basic** tier + role layer).
- **`spec/requests/plan_entitlements_matrix_spec.rb`** — storage entitlement on paid tiers.

**Related:** [plan_entitlements.md](plan_entitlements.md) (**`:file_storage`**), [storage_s3.md](../overall/storage_s3.md) (**mega #213**), [guild_role_permissions.md](guild_role_permissions.md), [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**), [guild_documents.md](guild_documents.md) (documents vs files gates), [authorization.md](../overall/authorization.md) (**mega #211**), [request_specs_and_gates.md](../overall/request_specs_and_gates.md).
