# frozen_string_literal: true

# Runs periodically to verify S3 (or S3-compatible) storage is working.
# Logs success to s3_verification.txt and failures to s3_errors.txt with descriptive messages.
class S3VerificationJob
  include Sidekiq::Worker

  def perform
    return unless s3_configured?

    bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"]
    endpoint = ENV["S3_ENDPOINT"].presence || ENV["AWS_S3_ENDPOINT"]
    region = ENV["S3_REGION"].presence || ENV["AWS_REGION"].presence || "eu-central-1"

    begin
      service = ActiveStorage::Blob.service
      unless service.is_a?(ActiveStorage::Service::S3Service)
        GuildsyncLoggers.info(GuildsyncLoggers.s3_verification, "S3 not in use - Active Storage service is #{service.class.name} (local disk). Set S3_* env vars to use S3.")
        return
      end

      # Use Active Storage to upload a tiny test blob (same path as real uploads)
      key = "s3_verification/#{Time.current.utc.to_i}.txt"
      io = StringIO.new("GuildSync S3 verification at #{Time.current.utc.iso8601}")
      service.upload(key, io, content_type: "text/plain")
      # Optionally delete the test object to avoid clutter (optional)
      service.delete(key) rescue nil

      msg = "S3 verification OK | bucket=#{bucket} | region=#{region} | endpoint=#{endpoint.presence || 'AWS default'}"
      GuildsyncLoggers.info(GuildsyncLoggers.s3_verification, msg)
      Rails.logger.info(msg)
    rescue Aws::S3::Errors::ServiceError => e
      log_s3_error("S3 service error", e, bucket: bucket, endpoint: endpoint, region: region)
    rescue Aws::Sigv4::Errors::MissingCredentialsError => e
      log_s3_error("S3 credentials missing or invalid", e, bucket: bucket, hint: "Check S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY (or AWS_* equivalents)")
    rescue Seahorse::Client::NetworkingError => e
      log_s3_error("S3 network error (timeout or unreachable)", e, bucket: bucket, endpoint: endpoint, hint: "Check S3_ENDPOINT and network/firewall")
    rescue Aws::S3::Errors::NoSuchBucket => e
      log_s3_error("S3 bucket does not exist or name typo", e, bucket: bucket, hint: "Create the bucket or fix S3_BUCKET / AWS_S3_BUCKET_NAME")
    rescue Aws::S3::Errors::InvalidAccessKeyId, Aws::S3::Errors::SignatureDoesNotMatch => e
      log_s3_error("S3 access key or secret invalid", e, bucket: bucket, hint: "Check S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY for typos or wrong credentials")
    rescue => e
      log_s3_error("S3 verification failed", e, bucket: bucket, endpoint: endpoint, region: region)
    end
  end

  private

  def s3_configured?
    bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"]
    key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"]
    secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"]
    bucket.present? && key.present? && secret.present?
  end

  def log_s3_error(title, exception, **context)
    msg = "#{title} | #{exception.class}: #{exception.message} | #{context.map { |k, v| "#{k}=#{v}" }.join(' | ')}"
    GuildsyncLoggers.error(GuildsyncLoggers.s3_errors, msg)
    GuildsyncLoggers.log_exception(GuildsyncLoggers.s3_errors, exception, context)
    Rails.logger.error(msg)
  end
end
