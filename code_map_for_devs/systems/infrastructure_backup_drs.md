# Infrastructure: object storage, backups, DRS (mega phase 15)

**Last updated:** 2026-05-19 (locales YAML in config snapshot tar)

**Mega plan:** This page tracks **what the Rails app actually contains** versus **production checklist §15** and admin §7 (DRS when shipped). It replaces an earlier stub that referenced classes **not present** in the repository.

## In the application today

### Active Storage and S3

- **Config:** `guildsync/config/storage.yml` (comments list attachment surfaces: avatars, guild/alliance logos, guild documents, guild file storage, etc.).
- **Production selection:** `guildsync/config/environments/production.rb` — `:amazon` when `S3_*` / `AWS_*` credentials, bucket, and `aws-sdk-s3` are available; otherwise **`:local` disk** (logged at boot). Override with **`ACTIVE_STORAGE_SERVICE`**.
- **Deep dive:** [`overall/storage_s3.md`](../overall/storage_s3.md).
- **Tests:** `spec/requests/active_storage_uploads_spec.rb`; optional real-bucket **`spec/requests/active_storage_real_s3_uploads_spec.rb`** when `REAL_S3_UPLOADS_IN_SPECS=1` / `ACTIVE_STORAGE_SERVICE=amazon`.

### Guild archive purge (application data lifecycle)

- **`Guild::ARCHIVE_RETENTION_PERIOD`** — **1 year** until `scheduled_purge_at`; then eligible for purge (see [`guilds_crud.md`](guilds_crud.md)).
- **Member-facing copy:** **`GET /guild_archives`** shows both the **one-year** archive **`subtitle`** and a separate **recovery note** (**~six months**, **deleted records** / support)—see [`guilds_crud.md`](guilds_crud.md); do not conflate the two timelines in docs or UX.
- **`PurgeArchivedGuildsJob`** — `Guild.purge_ready.find_each(&:purge!)`; destroys the guild record (cascades depend on associations). **Not** a Postgres/S3 bucket backup job.
- **Schedule (production Sidekiq):** `config/initializers/sidekiq.rb` — on Sidekiq **server** startup, a sleeper thread enqueues **`PurgeArchivedGuildsJob.perform_later`** daily at **5:00** server time (after first sleep). Requires **Sidekiq process running**; not enqueued from `rails server` alone.
- **Test:** `spec/jobs/purge_archived_guilds_job_spec.rb`.

### PostgreSQL dump to S3 (opt-in)

- **`DatabaseBackupToS3Service`** — `pg_dump` **custom format** (`-Fc`) using **`ActiveRecord::Base.connection_db_config`** (host, port, user, DB, `PGPASSWORD`); uploads via **`Aws::S3::Client`** with the same **`S3_*` / `AWS_*`** credentials and endpoint as Active Storage.
- **Enable:** `DATABASE_BACKUP_TO_S3_ENABLED=1`. **Bucket:** `DATABASE_BACKUP_S3_BUCKET` or fall back to **`S3_BUCKET`** / **`AWS_S3_BUCKET_NAME`** / **`AWS_BUCKET`**. **Key prefix:** `DATABASE_BACKUP_S3_PREFIX` (default **`database_backups/`**). Objects: `…/guildsync-{utc_timestamp}.dump`.
- **Rake:** `bin/rails infrastructure:database_backup_to_s3` (no-op message when disabled; **exit 1** on failure).
- **`DatabaseBackupToS3Job`** — **`ApplicationJob`** (`queue_as :low`); **monthly** enqueue **1st @ 06:00** server time from **`config/initializers/sidekiq.rb`** only if **`DATABASE_BACKUP_TO_S3_ENABLED=1` when Sidekiq starts** (restart Sidekiq after toggling).
- **Last-success metadata:** after a successful upload, **`DatabaseBackupToS3Service.record_last_success!`** writes **`Rails.cache`** under **`LAST_SUCCESS_CACHE_KEY`**; **`read_last_success`** exposes it for **`Admin::DatabaseBackupsController#show`** (**`GET /admin/database-backups`** — read-only; **10 locales** `admin.database_backups.*`).
- **Tests:** `spec/services/database_backup_to_s3_service_spec.rb` (including **`list_recent_backups`**), `spec/jobs/database_backup_to_s3_job_spec.rb`, `spec/requests/admin/database_backups_spec.rb`.
- **Object listing (admin):** **`DatabaseBackupToS3Service.list_recent_backups(max_keys:, continuation_token:)`** calls **`list_objects_v2`** on the backup **prefix** (default **100** keys per request). Each **page** is sorted by **LastModified** descending **within that page only**; S3’s global listing order is lexicographic, so ordering is **not** guaranteed across pages. **`GET /admin/database-backups?continuation_token=…`** passes a sanitized token (**8 KiB** max) to S3; the UI shows **Next page** (when **`is_truncated`**) and **Back to first page** when a token is active. IAM: **`s3:ListBucket`** on the bucket/prefix.
- **Gap:** **Decrypted** credentials / **ENV values** are not in the DB dump. **>6 month object deletion** remains **S3 lifecycle** (or ops).

### Config + schema snapshot to S3 (opt-in)

- **`ConfigSnapshotToS3Service`** — builds a **gzip tar** (`Gem::Package::TarWriter` + **`Zlib::GzipWriter`**) of **`config/*.yml`** (root only), **`config/locales/**/*.yml`**, **`config/environments/*.rb`**, **`config/initializers/*.rb`**, **`config/{boot,application,environment,routes}.rb`**, **`db/schema.rb`**, **`config/i18n-tasks.yml`**, and **`config/credentials.yml.enc`** when present. **Never** includes **`master.key`**, **`*.key`**, or **`.env`**. Initializers should load secrets from **ENV** / **credentials** only; the archive is still **sensitive** (schedules, integration wiring). Locale files are **product copy** (gzip shrinks the tree).
- **Enable:** `CONFIG_SNAPSHOT_TO_S3_ENABLED=1`. **Bucket:** `CONFIG_SNAPSHOT_S3_BUCKET` or fall back to the same chain as DB backups (`DATABASE_BACKUP_S3_BUCKET` / `S3_BUCKET` / …). **Prefix:** `CONFIG_SNAPSHOT_S3_PREFIX` (default **`config_snapshots/`**). Objects: `…/guildsync-config-{utc_timestamp}.tar.gz`.
- **Rake:** `bin/rails infrastructure:config_snapshot_to_s3` (no-op when disabled; **exit 1** on failure).
- **`ConfigSnapshotToS3Job`** — **`queue_as :low`**; **monthly** enqueue **1st @ 06:30** server time from **`config/initializers/sidekiq.rb`** when **`CONFIG_SNAPSHOT_TO_S3_ENABLED=1` at Sidekiq boot** (restart after toggling).
- **Last-success metadata:** **`record_last_success!`** writes **`Rails.cache`** under **`LAST_SUCCESS_CACHE_KEY`**; **`read_last_success`** for **`Admin::DatabaseBackupsController`** (same page as DB backups).
- **Object listing (admin):** **`list_recent_snapshots(max_keys:, continuation_token:)`** — same semantics as DB backup listing (**per-page** **`LastModified`** sort; **`config_continuation_token`** query param so it does not collide with DB **`continuation_token`**).
- **Tests:** `spec/services/config_snapshot_to_s3_service_spec.rb`, `spec/jobs/config_snapshot_to_s3_job_spec.rb`, `spec/requests/admin/database_backups_spec.rb` (config snapshot UI).
- **Ops:** add an S3 lifecycle rule on **`config_snapshots/`** mirroring **`database_backups/`** if retention should match.

### S3 lifecycle example (AWS — drop old `database_backups/` objects)

Apply at the **bucket** (console *Management* → *Lifecycle rules* or CloudFormation/Terraform). Adjust **180** days to your retention target; this is **not** executed by the Rails app.

```json
{
  "Rules": [
    {
      "ID": "ExpireGuildsyncDbDumps",
      "Status": "Enabled",
      "Filter": { "Prefix": "database_backups/" },
      "Expiration": { "Days": 180 }
    }
  ]
}
```

For **versioned** buckets, add **`NoncurrentVersionExpiration`** if you enable versioning on the same prefix. Other providers (MinIO, R2, etc.) expose equivalent lifecycle or expiry rules.

### Unrelated: MFA “backup codes”

- **`User` backup codes** (`backup_codes` table) are **account recovery**, not infrastructure backups.

## Product targets

| Target | Notes |
|--------|--------|
| DRS admin UI | **Partial:** **`Admin::DatabaseBackupsController`** — cache last success **+** **`list_objects_v2`** pages (**100** keys, **`continuation_token`** via query); Turbo Frame **`admin_database_backups_main`** for **`GET …/database-backups`** fragment responses. No in-app **>6 month** policy editor (use bucket lifecycle). |
| S3 versioning + lifecycle (e.g. drop objects **>6 months**) | **Bucket lifecycle** at provider; **example JSON** in this doc (`ExpireGuildsyncDbDumps`). |
| Image compression pipeline | Product/checklist item; tune processors where uploads are defined (see `overall/storage_s3.md`). |
| TLS / secrets-only | Hosting and `credentials`/ENV; not duplicated here. |
| Full config parity (non-locale config trees, e.g. `config/cable.yml`) in snapshots | **Partial:** **`ConfigSnapshotToS3Service`** covers **schema**, **root `config/*.yml`**, **`config/locales/**/*.yml`**, **environments**, **all `config/initializers/*.rb`**, core **`config/*.rb`**, **`config/i18n-tasks.yml`**, **`credentials.yml.enc`**; expand allowlist if policy demands more. |

## Related maps

- [`overall/storage_s3.md`](../overall/storage_s3.md) — Active Storage overview.
- [`guilds_crud.md`](guilds_crud.md) — archive, retention, purge specs.
- [`systems/storage_files.md`](storage_files.md) — `StorageController`, `FileEntry`.
