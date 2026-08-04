# Errors and observability

**Last updated:** 2026-04-16 — **`ErrorLogger`** call sites for **AI Stat Scanner** upload/OCR/Discord paths (see **`systems/ocr_ai_gear.md`**); mega **#196** baseline.

## Persistence (`ErrorLog`)

| Column / concern | Notes |
|------------------|--------|
| **`error_class`**, **`message`**, **`occurred_at`** | Required. |
| **`backtrace`** | Up to **200** frames joined (**`ErrorLogger`**). |
| **`context`** | JSONB; keep small (user id, guild id, action). |
| **`severity`** | **`ErrorLog::SEVERITIES`** → **`low`**, **`medium`**, **`high`**, **`urgent`**, **`stable`**. Invalid values in **`ErrorLogger.capture`** fall back to **`medium`**. |
| **`cause`** | Optional text (e.g. chained exception summary). |
| **`resolved_at`**, **`resolved_by`** | Set via **`ErrorLog#resolve!`** from admin UI. |

Indexes: **`occurred_at`**, **`resolved_at`**, **`severity`** (see **`db/schema.rb`**).

## Capture entry point — `ErrorLogger.capture`

**`app/services/error_logger.rb`**

```ruby
ErrorLogger.capture(exception, context: {}, severity: "medium", cause: nil)
```

- Truncates **`message`** to **10_000** chars.
- On success: **`ErrorDiscordNotifyJob.perform_later(record.id)`** when the job class is defined.
- On **`create!`** failure: logs **`[ErrorLogger]`** and returns **`nil`** (does not re-raise).

**Integration note:** Prefer **`capture`** over ad-hoc **`ErrorLog.create!`** so notify + validation stay consistent. **Production paths that call `ErrorLogger.capture` today include:** unexpected exceptions in **`GearOcrService.process_image`** (after OCR engine failure), outer **`GearController#upload`** rescue, embedding/attach rescues in **`GearController#upload`**, and **`DiscordGearService`** (image download, embedding, channel image handler). Routine validation failures (422, quota blocks) should **not** be logged here—only exceptional/infrastructure failures.

## `ErrorDiscordNotifyJob`

**`app/jobs/error_discord_notify_job.rb`** — **`queue_as :default`**. **`#perform` rescues `StandardError`** at the top so Sidekiq never fails the job for notify noise.

| Step | Behavior |
|------|----------|
| Load log | **`ErrorLog.find_by(id:)`** — no-op if missing. |
| Message body | Severity + class + truncated message (**~1600** in core line) + admin link. |
| Admin link | **`ENV["APP_URL"]`** + **`/admin/errors/:id`** if set; else **`admin_error_url`** helper; rescue → path **`/admin/errors/:id`**. |
| Webhook | **`ENV["ERROR_NOTIFY_DISCORD_WEBHOOK_URL"]`** — **`RestClient.post`** JSON **`{ "content": … }`**, content truncated to **`MAX_WEBHOOK_CONTENT` (1900)**. |
| DMs | Requires **`ENV["DISCORD_BOT_TOKEN"]`** + **`SiteSetting.error_notify_discord_usernames`**. Uses **`DiscordService.new(bot_token: token)`** and **`send_dm`** per resolved GuildSync user (**`LOWER(username)`** match). Usernames normalized: strip **`#discriminator`**. Body truncated to **`MAX_DM_LENGTH` (1800)**. |

Log grep tokens: **`[ErrorDiscordNotifyJob]`**, **`[ErrorLogger]`**.

## Configuration

- **`SiteSetting.error_notify_discord_usernames`** — JSON array string in DB; default in **`SiteSetting::DEFAULTS`** (see **`app/models/site_setting.rb`**). Parsed with fallback on **`JSON::ParserError`**.
- **`DISCORD_BOT_TOKEN`** — Same bot token family as gateway/HTTP Discord features; see **`overall/discord_bot.md`** for env overview (this job only needs DM-capable token).

## Admin UI

**`Admin::ErrorsController`** — index/show, resolve, bulk, destroy; Turbo streams on show/index (**mega #172**, **#173**); **`GET …/errors/:id`** lazy frame (**`admin_errors_show_main`**, **mega #228**). Detail: **`systems/admin_errors.md`**.

## Failure modes

- Webhook or DM failure → logged, **no** raise from job.
- Missing Discord user or missing **`user_discord_connection`** → warn log, skip that recipient.
- DB write failure inside **`ErrorLogger.capture`** → **`nil`** return; caller should still render a safe user response.

## Specs

| Spec | Focus |
|------|--------|
| **`spec/jobs/error_discord_notify_job_spec.rb`** | Missing log, webhook POST, DM path with stubbed **`DiscordService`**, truncation, failure absorption. |
| **`spec/requests/admin/errors_spec.rb`** | Admin Error Tracker HTTP + Turbo (**mega #172**, **#173**, **#228**). |

**Related:** [background_jobs.md](background_jobs.md), [discord_bot.md](discord_bot.md), [../systems/admin_errors.md](../systems/admin_errors.md).
