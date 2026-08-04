# frozen_string_literal: true

require "open3"
require "tempfile"

# Opt-in PostgreSQL backup to S3-compatible storage (pg_dump custom format).
#
# Enable: DATABASE_BACKUP_TO_S3_ENABLED=1
# Bucket: DATABASE_BACKUP_S3_BUCKET (optional; falls back to S3_BUCKET / AWS_S3_BUCKET_NAME / AWS_BUCKET)
# Prefix: DATABASE_BACKUP_S3_PREFIX (default database_backups/)
#
# Uses the same credential and endpoint env vars as Active Storage (`config/storage.yml`).
class DatabaseBackupToS3Service
  DEFAULT_PREFIX = "database_backups/"
  # Written after a successful upload; read by Admin::DatabaseBackupsController (Solid Cache / Rails.cache).
  LAST_SUCCESS_CACHE_KEY = "guildsync/database_backup/last_success"
  # Upper bound for S3 ListObjectsV2 continuation_token (query param + abuse guard).
  MAX_LIST_CONTINUATION_TOKEN_BYTES = 8192

  # Result of listing the backup prefix in S3 (admin UI).
  RecentBackupList = Struct.new(:entries, :truncated, :failed, :next_continuation_token, keyword_init: true)

  # Lists objects under the configured backup prefix (single ListObjectsV2 page).
  # Pass +continuation_token+ from the previous response's +next_continuation_token+ to walk additional pages.
  # Requires the same credentials as uploads plus s3:ListBucket on the bucket (scoped by prefix in IAM policies).
  def self.list_recent_backups(max_keys: 100, continuation_token: nil)
    new.list_recent_backups(max_keys: max_keys, continuation_token: continuation_token)
  end

  # Public so admin can echo the current page token in the UI; same rules as listing.
  def self.sanitize_list_continuation_token_param(raw)
    s = raw.to_s.strip
    return nil if s.blank?
    return nil if s.bytesize > MAX_LIST_CONTINUATION_TOKEN_BYTES

    s
  end

  def call
    return disabled_result unless enabled?

    bucket = backup_bucket_name
    return error_result("No S3 bucket configured (set DATABASE_BACKUP_S3_BUCKET or S3_BUCKET)") if bucket.blank?

    creds = s3_credentials
    return error_result("Missing S3 credentials (S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY or AWS_* equivalents)") unless creds[:ok]

    Tempfile.create([ "guildsync_pg_dump", ".dump" ]) do |tmp|
      tmp.binmode
      tmp.close
      unless run_pg_dump(tmp.path)
        return error_result("pg_dump failed (is `pg_dump` installed and DB reachable?)")
      end

      key = object_key
      upload_file(bucket:, key:, path: tmp.path)
      record_last_success!(key)
      { ok: true, disabled: false, key:, error: nil }
    end
  rescue Aws::S3::Errors::ServiceError => e
    error_result("S3 upload failed: #{e.class}: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[DatabaseBackupToS3Service] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    error_result(e.message)
  end

  def self.enabled?
    ENV["DATABASE_BACKUP_TO_S3_ENABLED"].to_s == "1"
  end

  def self.read_last_success
    Rails.cache.read(LAST_SUCCESS_CACHE_KEY)
  end

  def list_recent_backups(max_keys: 100, continuation_token: nil)
    return RecentBackupList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) unless self.class.enabled?

    bucket = backup_bucket_name
    return RecentBackupList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) if bucket.blank?

    creds = s3_credentials
    return RecentBackupList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) unless creds[:ok]

    cap = [ [ max_keys.to_i, 1 ].max, 1_000 ].min
    client = build_s3_client
    prefix = backup_prefix
    token = self.class.sanitize_list_continuation_token_param(continuation_token)
    list_args = { bucket: bucket, prefix: prefix, max_keys: cap }
    list_args[:continuation_token] = token if token.present?
    resp = client.list_objects_v2(**list_args)
    raw = resp.contents || []
    entries = raw.map do |obj|
      {
        key: obj.key,
        size: obj.size,
        last_modified: obj.last_modified&.utc&.iso8601(3)
      }
    end
    entries.sort_by! { |h| h[:last_modified].to_s }
    entries.reverse!
    next_tok = resp.is_truncated ? resp.next_continuation_token : nil
    RecentBackupList.new(
      entries: entries,
      truncated: resp.is_truncated,
      failed: false,
      next_continuation_token: next_tok
    )
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[DatabaseBackupToS3Service] list_objects_v2 failed: #{e.class}: #{e.message}")
    RecentBackupList.new(entries: [], truncated: false, failed: true, next_continuation_token: nil)
  end

  private

  def enabled?
    self.class.enabled?
  end

  def disabled_result
    { ok: true, disabled: true, key: nil, error: nil }
  end

  def error_result(message)
    { ok: false, disabled: false, key: nil, error: message.to_s }
  end

  def backup_bucket_name
    ENV["DATABASE_BACKUP_S3_BUCKET"].presence ||
      ENV["S3_BUCKET"].presence ||
      ENV["AWS_S3_BUCKET_NAME"].presence ||
      ENV["AWS_BUCKET"].presence
  end

  def backup_prefix
    ENV.fetch("DATABASE_BACKUP_S3_PREFIX", DEFAULT_PREFIX).to_s.sub(%r{\A/*}, "").sub(%r{/*\z}, "") + "/"
  end

  def object_key
    stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    "#{backup_prefix}guildsync-#{stamp}.dump"
  end

  def s3_credentials
    key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"].presence
    secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"].presence
    { ok: key.present? && secret.present?, access_key_id: key, secret_access_key: secret }
  end

  def build_s3_client
    require "aws-sdk-s3"
    c = s3_credentials
    region = ENV["S3_REGION"].presence || ENV["AWS_REGION"].presence || "eu-central-1"
    endpoint = ENV["S3_ENDPOINT"].presence || ENV["AWS_S3_ENDPOINT"]
    opts = {
      region: region,
      access_key_id: c[:access_key_id],
      secret_access_key: c[:secret_access_key]
    }
    if endpoint.present?
      opts[:endpoint] = endpoint.to_s.sub(%r{/+\z}, "")
      opts[:force_path_style] = true
    end
    Aws::S3::Client.new(opts)
  end

  def upload_file(bucket:, key:, path:)
    client = build_s3_client
    body = File.binread(path)
    args = { bucket: bucket, key: key, body: body, content_type: "application/octet-stream" }
    args[:server_side_encryption] = "AES256" if ENV["S3_SSE_AES256"].to_s == "1"
    client.put_object(**args)
  end

  def record_last_success!(s3_key)
    payload = { "s3_key" => s3_key, "finished_at" => Time.current.utc.iso8601(3) }
    Rails.cache.write(LAST_SUCCESS_CACHE_KEY, payload, expires_in: 10.years)
  end

  def run_pg_dump(output_path)
    cfg = ActiveRecord::Base.connection_db_config
    h = cfg.configuration_hash
    database = h[:database] || h["database"]
    username = h[:username] || h["username"]
    host = (h[:host] || h["host"]).presence || "127.0.0.1"
    port = (h[:port] || h["port"]).presence || 5432
    password = h[:password] || h["password"]

    return false if database.blank? || username.blank?

    env = {}
    env["PGPASSWORD"] = password.to_s if password.present?
    cmd = [
      "pg_dump",
      "-h", host.to_s,
      "-p", port.to_s,
      "-U", username.to_s,
      "-d", database.to_s,
      "--no-owner",
      "--no-acl",
      "-Fc",
      "-f", output_path
    ]
    _out, err, status = Open3.capture3(env, *cmd)
    unless status.success?
      Rails.logger.error("[DatabaseBackupToS3Service] pg_dump stderr: #{err.presence || '(empty)'}")
    end
    status.success?
  end
end
