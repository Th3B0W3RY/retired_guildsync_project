# Storage and S3 (Active Storage)

**Last updated:** 2026-04-07 (admin homepage feature-card editor images now upload via Active Storage/S3; production ACL guard rejects public-read ACL env values)

GuildSync uses **Rails Active Storage** for user-uploaded blobs. **HTTP flows, plan limits, and MFA** for the file browser live in **[systems/storage_files.md](../systems/storage_files.md)** (**mega #186**).

## Configuration files

| File | Role |
|------|------|
| **`guildsync/config/storage.yml`** | Named services: **`:test`**, **`:local`** (Disk), **`:amazon`** (S3-compatible via **`aws-sdk-s3`**). Comments document **ACL / SSE** pitfalls (bucket owner enforced, optional **`S3_SSE_AES256`**, **`S3_ACL`** / **`none`**). Upload YAML now only passes `acl` when explicitly private (`private` or `bucket-owner-full-control`). |
| **`guildsync/config/initializers/active_storage_acl_guard.rb`** | Production boot-time guard: raises if **`S3_ACL`** / **`AWS_S3_ACL`** is set to unsafe public ACL values (`public-read`, `public-read-write`, `authenticated-read`). |
| **`guildsync/config/environments/production.rb`** | **`ACTIVE_STORAGE_SERVICE`** forces a symbol; else **`:amazon`** when bucket + key + secret + gem load OK, otherwise **`:local`** with a console warning listing missing pieces. |
| **`guildsync/config/environments/development.rb`** | Default **`:local`**. **`ACTIVE_STORAGE_SERVICE`** override, or **`USE_S3_IN_DEVELOPMENT=1`** + full S3 env + gem → **`:amazon`**. |
| **`guildsync/config/environments/test.rb`** | Default **`:test`** (disk under **`tmp/storage`**). If **`ACTIVE_STORAGE_SERVICE=amazon`**, uses **`:amazon`** only when **`REAL_S3_UPLOADS_IN_SPECS=1`** (pairs with **`spec/requests/active_storage_real_s3_uploads_spec.rb`**). |

## S3-compatible **`:amazon`** service (summary)

**Env (see `storage.yml` for full list):** **`S3_ACCESS_KEY_ID`** / **`AWS_ACCESS_KEY_ID`**, **`S3_SECRET_ACCESS_KEY`** / **`AWS_SECRET_ACCESS_KEY`**, **`S3_BUCKET`** / **`AWS_S3_BUCKET_NAME`** / **`AWS_BUCKET`**, **`S3_REGION`** / **`AWS_REGION`** (default **`eu-central-1`** in YAML), optional **`S3_ENDPOINT`** for non-AWS providers (**`force_path_style: true`**).

**Upload options in YAML:** **`cache_control`**, optional **`server_side_encryption`**, optional **`acl`**.

## Models with **`has_one_attached`** (repo scan)

| Model | Attachment | Notes |
|-------|------------|--------|
| **`User`** | **`avatar`** | **`ValidatesImageAttachment`** |
| **`Guild`** | **`logo`** | **`ValidatesImageAttachment`** |
| **`Alliance`** | **`logo`** | **`ValidatesImageAttachment`** |
| **`GuildDocumentImage`** | **`image`** | Document inline images |
| **`ActiveStorage::Blob` (direct blob upload endpoint)** | n/a (blob row) | Admin homepage feature-card editor image uploads (`POST /admin/homepage-feature-cards/upload_image`) |
| **`GearSnapshot`** | **`screenshot`** | Gear / OCR flow |
| **`FileEntry`** | **`file`** | Guild file storage; **`after_commit`** compression path when **`compressible?`** — see **`storage_files.md`** / jobs inventory |

*Other binary data may use custom columns or external systems; this list is Active Storage attachments only.*

## Operations vs user uploads

**RDS/config backups** and **admin DRS** are **not** Active Storage — see **[systems/infrastructure_backup_drs.md](../systems/infrastructure_backup_drs.md)**.

## Spec pointers

- **Real S3 (opt-in):** **`spec/requests/active_storage_real_s3_uploads_spec.rb`**
- **Guild storage HTTP + gates:** **`storage_spec`**, **`file_entries_spec`** — see **`storage_files.md`**

**Related:** [storage_files.md](../systems/storage_files.md), [background_jobs.md](background_jobs.md), [data_model_core.md](data_model_core.md).
