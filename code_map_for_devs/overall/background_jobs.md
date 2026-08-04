# Background jobs

**Last updated:** 2026-04-06 (mega **#212** — `LootRollDeadlineJob` ops note + **`spec/jobs/loot_roll_deadline_job_spec`**, staggered 6-hourly threads, cross-links to feature maps; inventory + **`sidekiq.rb`** table unchanged in spirit)

## Runtime

| Piece | Location / notes |
|-------|-------------------|
| **Adapter** | **`config.active_job.queue_adapter`** — **`:sidekiq`** in **development** / **production**; **`:test`** in **test** (`config/environments/*.rb`). |
| **Base class** | **`ApplicationJob < ActiveJob::Base`** — **`retry_on ActiveRecord::Deadlocked`**, **`discard_on ActiveJob::DeserializationError`**. |
| **Sidekiq** | Redis URL via **`RedisConfig.sidekiq_url`**; Web UI mounted with **`SidekiqAdminAuth`** (session **`admin_authenticated`**) — see **`config/initializers/sidekiq.rb`**. TLS: if **`REDIS_URL`** uses the **`rediss://`** scheme, **`RedisConfig.ssl_options_for`** automatically adds **`ssl: true` / `ssl_params`** to both server and client config. Set **`REDIS_SSL_VERIFY_NONE=1`** for self-signed certs. |
| **Two enqueue styles** | **`ApplicationJob`** subclasses: use **`perform_later`** (and **`set(wait: …)`**) from app code. Plain **Sidekiq** workers (**`include Sidekiq::Worker`** or **`Sidekiq::Job`**): use **`perform_async`** / **`perform_bulk`**. The periodic scheduler in **`sidekiq.rb`** mostly calls **`perform_async`**; several targets are still **`ApplicationJob`** subclasses (they run through Sidekiq when the adapter is active—if enqueue ever errors, switch that line to **`perform_later`**). |

## Periodic scheduling (`config/initializers/sidekiq.rb`)

All intervals are **`Sidekiq.configure_server` → `on(:startup)`** **`Thread.new { loop … }`** (not **sidekiq-cron**). Summary:

| Cadence | Job(s) enqueued |
|---------|------------------|
| **10 min** | **`DiscordBotPresenceCheckJob.perform_later`** |
| **30 min** | **`DiscordRoleRefreshJob`**, **`MarkOutdatedGearSnapshotsJob`** — **`perform_async`** |
| **Daily ~2 AM** | **`SyncGamesWithIgdbJob`** — **`perform_async`** |
| **Daily ~3 AM** | **`ExpireTrialsJob`**, **`GuildActivityLogPruneJob`** + **`AllianceActivityLogPruneJob`** — **`perform_async`** |
| **Daily ~4 AM** | **`S3VerificationJob`** — **`perform_async`** |
| **Daily ~4:30 AM** | **`CleanupErrorLogsJob`** — **`perform_async`** |
| **Daily ~5 AM** | **`PurgeArchivedGuildsJob.perform_later`** |
| **Every 6 h** (staggered start) | **`CriticalJobsMonitorJob`**, **`ContentModerationHealthCheckJob`**, **`ProfanityListUpdateJob`** — **`perform_async`** |
| **~5× / day** | **`IpMembershipAuditJob`** — **`perform_async`** |
| **90 days** | **`LogRotationJob`** — **`perform_async`** |
| **Monthly 1st 06:00** | **`DatabaseBackupToS3Job.perform_later`** if **`ENV["DATABASE_BACKUP_TO_S3_ENABLED"] == "1"`** at Sidekiq boot (`beginning_of_month.change(hour: 6)`) |
| **Monthly 1st 06:30** | **`ConfigSnapshotToS3Job.perform_later`** if **`ENV["CONFIG_SNAPSHOT_TO_S3_ENABLED"] == "1"`** at boot (`hour: 6, min: 30`) |

**Staggered cold start:** the **6-hour** loops do not all fire at once on process boot — **`CriticalJobsMonitorJob`** sleeps **60s** before its first enqueue; **`ContentModerationHealthCheckJob`** **120s**; **`ProfanityListUpdateJob`** **180s**; **`IpMembershipAuditJob`** **240s** (then each uses its own interval). Useful when correlating “first wave” logs after deploy.

Admin **manual** enqueue: **`Admin::ContentModerationController`** — **`ContentModerationHealthCheckJob.perform_async`**, **`ProfanityListUpdateJob.perform_async`** (see **`content_moderation_spec`**).

## Not scheduled in `sidekiq.rb` (operator action)

| Job | Role |
|-----|------|
| **`LootRollDeadlineJob`** | **`ApplicationJob`** — finds **`LootRoll.open`** with **`deadline_at <= Time.current`**, **`close_and_determine_winner!`**, **`DiscordLootRollService#update_loot_roll_message`**, **`LootRollsChannel.broadcast_update`**. Class comment expects **cron / external scheduling**; there is **no** `Thread.new` / `perform_later` hook in **`config/initializers/sidekiq.rb`**. Production must enqueue on an interval (e.g. **every minute** host cron → `rails runner` / **Sidekiq-scheduler** / **K8s CronJob**) or add an explicit loop in **`sidekiq.rb`**. Web UX: [`../systems/guild_polls_loot_rolls.md`](../systems/guild_polls_loot_rolls.md) (**mega #210**). |

## Cross-links to feature maps

| Job(s) | Where to read |
|--------|----------------|
| **`PurgeArchivedGuildsJob`** | [`../systems/guilds_crud.md`](../systems/guilds_crud.md) (archive + purge), [`../systems/infrastructure_backup_drs.md`](../systems/infrastructure_backup_drs.md) |
| **`GuildActivityLogPruneJob`**, **`AllianceActivityLogPruneJob`** | [`../systems/activity_feed.md`](../systems/activity_feed.md), [`../systems/alliances.md`](../systems/alliances.md) |
| **`DatabaseBackupToS3Job`**, **`ConfigSnapshotToS3Job`**, **`S3VerificationJob`** | [`../systems/infrastructure_backup_drs.md`](../systems/infrastructure_backup_drs.md), [`storage_s3.md`](storage_s3.md) |
| **`DiscordGearRequestJob`**, **`DiscordBulkGearRequestJob`**, **`MarkOutdatedGearSnapshotsJob`** | [`../systems/ocr_ai_gear.md`](../systems/ocr_ai_gear.md), [`discord_bot.md`](discord_bot.md) |
| **`DiscordInteractionJob`**, **`DiscordCommandJob`**, bot join/presence | [`discord_bot.md`](discord_bot.md) |
| **`ErrorDiscordNotifyJob`**, **`CleanupErrorLogsJob`** | [`error_observability.md`](error_observability.md) |
| **`ExpireTrialsJob`** | [`../systems/billing_trial_policy.md`](../systems/billing_trial_policy.md), [`../systems/subscriptions_user.md`](../systems/subscriptions_user.md) |
| **`SearchIndexJob`** | Enqueued when search-indexable records change (see callers); plan matrix unrelated |

## Job inventory (`app/jobs/`)

### `ApplicationJob` subclasses (`perform_later` in app code)

`CleanupErrorLogsJob`, `ConfigSnapshotToS3Job`, `DatabaseBackupToS3Job`, `DiscordBotJoinJob`, `DiscordBotPresenceCheckJob`, `DiscordBulkGearRequestJob`, `DiscordCommandJob`, `DiscordGearRequestJob`, `DiscordInteractionJob`, `DiscordPostEventJob`, `DiscordUpdateEventParticipantsJob`, `ErrorDiscordNotifyJob`, `GuildWarningDiscordDmJob`, `LootRollDeadlineJob`, `MarkOutdatedGearSnapshotsJob`, `NotifyAdminsGameActivationRequestJob`, `PurgeArchivedGuildsJob`, `SearchIndexJob`, `SyncGamesWithIgdbJob`.

### Sidekiq-native (`perform_async`)

**`Sidekiq::Worker`:** `AllianceActivityLogPruneJob`, `ContentModerationHealthCheckJob`, `CriticalJobsMonitorJob`, `DiscordCommandExecutionCleanupJob`, `DiscordRoleRefreshJob`, `ExpireTrialsJob`, `GuildActivityLogPruneJob`, `IpMembershipAuditJob`, `LogRotationJob`, `ProfanityListUpdateJob`, `S3VerificationJob`.

**`Sidekiq::Job`:** `FileCompressionJob` (enqueued from **`FileEntry`** model).

## Failure modes

- **`config.death_handlers`** in **`sidekiq.rb`** logs permanent failures.
- External APIs (Discord, IGDB, S3, webhooks): **rescue**, log, avoid silent **`rescue nil`**.
- Prefer **idempotent** **`perform`** where retries or duplicate enqueues are possible.

## Specs

- **`spec/jobs/**`** — per-job examples where present (e.g. **`error_discord_notify_job_spec`**, **`critical_jobs_monitor_job_spec`**, **`loot_roll_deadline_job_spec`** — **`LootRollDeadlineJob`** closes past-**`deadline_at`** rolls, stubs Discord + Cable, ignores future/nil deadlines).
- Request specs that stub **`perform_async`** / **`perform_later`** at enqueue sites (admin moderation, user restoration, etc.).

**Related:** [error_observability.md](error_observability.md) (`ErrorDiscordNotifyJob`), [discord_bot.md](discord_bot.md) (Discord jobs), [authorization.md](authorization.md) (gates vs jobs), `systems/stripe_webhooks.md`, `systems/infrastructure_backup_drs.md` (DB/config S3 jobs), [`../systems/guild_polls_loot_rolls.md`](../systems/guild_polls_loot_rolls.md) (`LootRollDeadlineJob`).
