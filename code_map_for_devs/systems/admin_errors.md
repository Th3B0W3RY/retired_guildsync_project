# Admin error tracker

**Last updated:** 2026-04-06 (**mega #228** show Turbo Frame; **`error_show_refresh`** **mega #173**)

## Routes

- **`namespace :admin`** — `resources :errors, controller: "errors", only: [ :index, :show, :destroy ]` (see `config/routes.rb`). Path helpers prefixed with `admin_` (e.g. `admin_errors_path`, `admin_error_path`).

## Controller & model

- **`Admin::ErrorsController`** — Lists `ErrorLog` rows; show detail; **member `resolve`**, **collection `bulk_action`** (resolve/delete), **destroy**. Flash copy and all Error Tracker UI strings use **`t("admin.errors.*")`** in **`config/locales/<locale>/admin.<locale>.yml`** (10 locales); pluralized flashes for bulk use **`admin.errors.flash.bulk_resolved`** / **`bulk_deleted`** with `count`. **`GET …/errors/:id`**: **`Turbo-Frame: admin_errors_show_main`** → **`errors_show_frame`** (**`layout: false`**); full **`show`** wraps the same **`turbo-frame`** around **`admin_error_show_flash`** + **`_show_main`** so lazy frame loads match full-page DOM and **`error_show_refresh`** (**mega #173**) keeps working. **Back to list** on show uses **`data-turbo-frame="_top"`**; index **view** links already **`_top`** (**mega #228**). **`#resolve`** **`format.turbo_stream`** — **`error_show_refresh.turbo_stream.erb`** updates **`admin_error_show_flash`** (**`_flash_banner`**) and replaces **`admin_error_show_main`** (**`_show_main`**) so the show page does not full-page reload (**mega #173**).
- **`ErrorLog`** — Persists captured exceptions (`ErrorLogger`); **`severity`** (e.g. low / medium / high / urgent / stable), cause, backtrace metadata.
- **`ErrorDiscordNotifyJob`** — After capture, optional **webhook** (`ERROR_NOTIFY_DISCORD_WEBHOOK_URL`) and/or **DMs** to users in **`SiteSetting.error_notify_discord_usernames`** when **`DISCORD_BOT_TOKEN`** is set. See [overall/error_observability.md](../overall/error_observability.md).

## Failure modes

- Discord notify path must not break capture (see `ErrorDiscordNotifyJob` + [overall/error_observability.md](../overall/error_observability.md)).
- Inner errors in notify pipeline should be rescued and logged.

## Specs

- **`spec/requests/admin/errors_spec.rb`**

**Related:** `systems/admin_dashboard.md`, [overall/error_observability.md](../overall/error_observability.md).
