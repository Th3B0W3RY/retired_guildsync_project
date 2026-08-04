# frozen_string_literal: true

# Log S3 upload/download failures to dedicated s3_errors.txt with descriptive messages.
return unless defined?(ActiveStorage::Service::S3Service)

module ActiveStorageS3ErrorLogging
  def upload(key, io, **options)
    super
  rescue Aws::S3::Errors::ServiceError => e
    log_s3_failure("upload", key, e, "S3 service error (bucket/perms/endpoint)")
    raise
  rescue Seahorse::Client::NetworkingError => e
    log_s3_failure("upload", key, e, "Network timeout or endpoint unreachable - check S3_ENDPOINT and firewall")
    raise
  rescue Aws::Sigv4::Errors::MissingCredentialsError => e
    log_s3_failure("upload", key, e, "Credentials missing - check S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY")
    raise
  rescue Aws::S3::Errors::NoSuchBucket => e
    log_s3_failure("upload", key, e, "Bucket does not exist or S3_BUCKET typo")
    raise
  rescue Aws::S3::Errors::InvalidAccessKeyId, Aws::S3::Errors::SignatureDoesNotMatch => e
    log_s3_failure("upload", key, e, "Invalid access key or secret - check credentials")
    raise
  rescue => e
    log_s3_failure("upload", key, e, "Unexpected error")
    raise
  end

  def download(key)
    super
  rescue Aws::S3::Errors::ServiceError => e
    log_s3_failure("download", key, e, "S3 service error")
    raise
  rescue Seahorse::Client::NetworkingError => e
    log_s3_failure("download", key, e, "Network timeout or unreachable")
    raise
  rescue => e
    log_s3_failure("download", key, e, "Download failed")
    raise
  end

  private

  def log_s3_failure(operation, key, exception, hint)
    return unless defined?(GuildsyncLoggers)

    bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || "unknown"
    msg = "Active Storage S3 #{operation} failed | key=#{key} | bucket=#{bucket} | #{exception.class}: #{exception.message} | hint: #{hint}"
    GuildsyncLoggers.error(GuildsyncLoggers.s3_errors, msg)
    GuildsyncLoggers.log_exception(GuildsyncLoggers.s3_errors, exception, operation: operation, key: key)
  end
end

ActiveStorage::Service::S3Service.prepend(ActiveStorageS3ErrorLogging)
