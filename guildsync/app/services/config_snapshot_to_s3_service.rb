# frozen_string_literal: true

require "rubygems/package"
require "stringio"
require "zlib"

# Opt-in tarball of non-secret Rails config + schema for disaster recovery documentation.
#
# Enable: CONFIG_SNAPSHOT_TO_S3_ENABLED=1
# Bucket: CONFIG_SNAPSHOT_S3_BUCKET (optional; falls back to DATABASE_BACKUP_S3_BUCKET / S3_BUCKET / AWS_S3_BUCKET_NAME / AWS_BUCKET)
# Prefix: CONFIG_SNAPSHOT_S3_PREFIX (default config_snapshots/)
#
# Includes: config/*.yml (root only), config/locales/**/*.yml, config/environments/*.rb, config/initializers/*.rb,
#           core config/*.rb, db/schema.rb, config/credentials.yml.enc when present (encrypted blob only — keep master.key out of band).
# Excludes: master.key, *.key, .env — never bundled.
#
# Initializers often read secrets from ENV or credentials — do not hardcode API keys in tracked Ruby; treat the tar as
# sensitive (structure + non-secret config still aids DRS runbooks).
#
# Uses the same S3 credential env vars as Active Storage (`config/storage.yml`).
class ConfigSnapshotToS3Service
  DEFAULT_PREFIX = "config_snapshots/"
  REJECT_BASENAMES = %w[master.key].freeze
  # Written after a successful upload; read by Admin::DatabaseBackupsController (Rails.cache).
  LAST_SUCCESS_CACHE_KEY = "guildsync/config_snapshot/last_success"

  # Result of listing the config snapshot prefix in S3 (admin UI).
  RecentConfigSnapshotList = Struct.new(:entries, :truncated, :failed, :next_continuation_token, keyword_init: true)

  def call
    return disabled_result unless enabled?

    bucket = snapshot_bucket_name
    return error_result("No S3 bucket configured (set CONFIG_SNAPSHOT_S3_BUCKET or DATABASE_BACKUP_S3_BUCKET or S3_BUCKET)") if bucket.blank?

    creds = s3_credentials
    return error_result("Missing S3 credentials (S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY or AWS_* equivalents)") unless creds[:ok]

    body = build_archive_bytes
    return error_result("No files collected for config snapshot (check Rails.root)") if body.blank?

    key = object_key
    upload_file(bucket:, key:, body:)
    record_last_success!(key)
    { ok: true, disabled: false, key:, error: nil }
  rescue Aws::S3::Errors::ServiceError => e
    error_result("S3 upload failed: #{e.class}: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[ConfigSnapshotToS3Service] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    error_result(e.message)
  end

  def self.enabled?
    ENV["CONFIG_SNAPSHOT_TO_S3_ENABLED"].to_s == "1"
  end

  def self.read_last_success
    Rails.cache.read(LAST_SUCCESS_CACHE_KEY)
  end

  # Lists objects under CONFIG_SNAPSHOT_S3_PREFIX (single ListObjectsV2 page).
  def self.list_recent_snapshots(max_keys: 100, continuation_token: nil)
    new.list_recent_snapshots(max_keys: max_keys, continuation_token: continuation_token)
  end

  def list_recent_snapshots(max_keys: 100, continuation_token: nil)
    return RecentConfigSnapshotList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) unless self.class.enabled?

    bucket = snapshot_bucket_name
    return RecentConfigSnapshotList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) if bucket.blank?

    creds = s3_credentials
    return RecentConfigSnapshotList.new(entries: [], truncated: false, failed: false, next_continuation_token: nil) unless creds[:ok]

    cap = [ [ max_keys.to_i, 1 ].max, 1_000 ].min
    client = build_s3_client
    prefix = snapshot_prefix
    token = DatabaseBackupToS3Service.sanitize_list_continuation_token_param(continuation_token)
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
    RecentConfigSnapshotList.new(
      entries: entries,
      truncated: resp.is_truncated,
      failed: false,
      next_continuation_token: next_tok
    )
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[ConfigSnapshotToS3Service] list_objects_v2 failed: #{e.class}: #{e.message}")
    RecentConfigSnapshotList.new(entries: [], truncated: false, failed: true, next_continuation_token: nil)
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

  def snapshot_bucket_name
    ENV["CONFIG_SNAPSHOT_S3_BUCKET"].presence ||
      ENV["DATABASE_BACKUP_S3_BUCKET"].presence ||
      ENV["S3_BUCKET"].presence ||
      ENV["AWS_S3_BUCKET_NAME"].presence ||
      ENV["AWS_BUCKET"].presence
  end

  def snapshot_prefix
    ENV.fetch("CONFIG_SNAPSHOT_S3_PREFIX", DEFAULT_PREFIX).to_s.sub(%r{\A/*}, "").sub(%r{/*\z}, "") + "/"
  end

  def object_key
    stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    "#{snapshot_prefix}guildsync-config-#{stamp}.tar.gz"
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

  def upload_file(bucket:, key:, body:)
    client = build_s3_client
    args = { bucket: bucket, key: key, body: body, content_type: "application/gzip" }
    args[:server_side_encryption] = "AES256" if ENV["S3_SSE_AES256"].to_s == "1"
    client.put_object(**args)
  end

  def record_last_success!(s3_key)
    payload = { "s3_key" => s3_key, "finished_at" => Time.current.utc.iso8601(3) }
    Rails.cache.write(LAST_SUCCESS_CACHE_KEY, payload, expires_in: 10.years)
  end

  def relative_paths_for_snapshot
    root = Rails.root
    paths = []

    %w[
      config/boot.rb
      config/application.rb
      config/environment.rb
      config/routes.rb
      db/schema.rb
      config/i18n-tasks.yml
    ].each do |rel|
      paths << rel if root.join(rel).file?
    end

    Dir.glob(root.join("config/*.yml")).sort.each do |abs|
      next unless File.file?(abs)

      bn = File.basename(abs)
      next if REJECT_BASENAMES.include?(bn)

      paths << Pathname.new(abs).relative_path_from(root).to_s.tr("\\", "/")
    end

    Dir.glob(root.join("config/environments/*.rb")).sort.each do |abs|
      paths << Pathname.new(abs).relative_path_from(root).to_s.tr("\\", "/") if File.file?(abs)
    end

    Dir.glob(root.join("config/initializers/*.rb")).sort.each do |abs|
      paths << Pathname.new(abs).relative_path_from(root).to_s.tr("\\", "/") if File.file?(abs)
    end

    Dir.glob(root.join("config/locales/**/*.yml")).sort.each do |abs|
      paths << Pathname.new(abs).relative_path_from(root).to_s.tr("\\", "/") if File.file?(abs)
    end

    cred_enc = root.join("config/credentials.yml.enc")
    paths << "config/credentials.yml.enc" if cred_enc.file?

    paths.uniq.sort
  end

  def build_archive_bytes
    pairs = relative_paths_for_snapshot.filter_map do |rel|
      full = Rails.root.join(rel)
      next unless full.file?

      next if rel.end_with?(".key")
      next if rel.include?("/.env") || rel == ".env"

      [ rel, full ]
    end
    return +"" if pairs.empty?

    io = StringIO.new(String.new(encoding: Encoding::BINARY))
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        pairs.each do |rel, full|
          content = File.binread(full)
          tar.add_file_simple(rel, 0o644, content.bytesize) { |dst| dst.write(content) }
        end
      end
    end
    io.string
  end
end
