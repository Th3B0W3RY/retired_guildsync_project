# Activity feed (guild activity log UI + CSV export)

**Alliance counterpart:** **`GET /alliances/:alliance_id/activity_feed`** — member chrome **`support_center_url`** on HTML **index** only (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 319**, **`alliance_activity_feed_spec`**); **`alliances.md`**.

**Last updated:** 2026-04-16 — **`gear_uploaded`** rows from **`GearStatScanActivityLog`** after stat-scanner uploads (web + Discord): description uses **`gear.activity.uploaded`** or **`gear.activity.uploaded_shared_guild_plan`** when OCR is billed to the guild leader; optional metadata **`ocr_billed_to_name`**. (2026-04-06 — **`activity_feed_spec`** **`GET /guilds/:id/activity_feed`** **`support_center_url`** — **changelog 283**; **`alliance_activity_feed_spec`** alliance **`GET …/activity_feed`** — **changelog 319**, **Lane C**)

## Routes & controller

- **Controller:** `guildsync/app/controllers/activity_feed_controller.rb`
- **Routes (guild-scoped):** `GET /guilds/:id/activity_feed` → `index`; `GET /guilds/:id/activity_feed/export` → `export` (CSV attachment).
- **Concerns / filters:** `authenticate_user!` → `set_guild` → `require_active_guild_access` → `require_activity_feed_access`.

## Guild resolution (`set_guild`)

Resolves `@guild` only when the user is tied to that guild (same idea as **`MessageCenterController`** / file storage):

1. `current_user.guilds.find_by(id: params[:id])`
2. else `current_user.owned_guilds.find_by(id: …)`
3. else `Guild.find_by(id: …, owner_id: current_user.id)`

If none match → **`my_guilds_path`** + **`t("controllers.guilds.access_denied")`** (stops ID probing across unrelated guilds).

## Access gates (`require_activity_feed_access`)

Order matters:

1. **`plan_allows?(:activity_feed)`** — if false → **`upgrade_pricing_path`** + **`plan_entitlements.upgrade_required`**.
2. **`can_view_activity_feed?(@guild)`** — if false → **`guild_path(@guild)`** + **`activity_feed.access_denied`**.

## Index vs export

- **`index`:** Paginated **`GuildActivityLog.for_guild(@guild)`** via **`guild_activity_logs_scope`**, `PER_PAGE = 25`, optional filters:
  - **`action_type`**, **`user_id`**, **`q`** (ILIKE on `description` and `metadata::text`; uses **`sanitize_sql_like`**).
- **`export`:** Same scope as index (no pagination) → **CSV** with headers:
  - `time_utc`, `guildsync_username`, `action`, `details`, `metadata_json`
  - Action label via **`helpers.format_activity_action_type`**.

Both actions call **`preserve_session`** (keeps Devise/MFA session fields warm for long-lived tabs).

## Failure / abuse modes

- Unknown guild id or no membership → redirect **`my_guilds_path`** + guild **`access_denied`** (no 404 leak).
- Plan without activity feed → pricing upgrade alert.
- Role/plan matrix denies view → guild dashboard + **`activity_feed.access_denied`**.

## Specs

- **`spec/requests/activity_feed_spec.rb`** — sidebar link; **`GET …/activity_feed`** — **`support_center_url`** in member chrome (default + custom **`SiteSetting`**, desktop + **`:mobile`** — **changelog 283**); CSV export happy path, filters, **`GET …/export`** blocked for **stranger** (signed-in user with Basic plan but **no** guild access) → **`my_guilds_path`** + **`access_denied`** (mega **#96** alignment).
- **`spec/requests/guild_permissions_matrix_spec.rb`** — role flag vs activity feed pages.
- **`spec/requests/plan_entitlements_matrix_spec.rb`** — plan tier vs activity feed.

## Alliance note

Alliance-scoped activity feed lives under **alliance** routes/controllers (see **`alliance_free_member_access_spec`** and **`request_specs_and_gates.md`**). This page documents the **guild** `ActivityFeedController` only.

**Related:** [request_specs_and_gates.md](../overall/request_specs_and_gates.md), [plan_entitlements.md](plan_entitlements.md) (**`:activity_feed`**), [authorization.md](../overall/authorization.md) (**mega #211** — plan + role layers vs hybrid **`can_*`**), [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**), [message_center.md](message_center.md) (same **`set_guild`** pattern), [warnings.md](warnings.md) (**mega #180** — parallel plan-gated guild feed).
