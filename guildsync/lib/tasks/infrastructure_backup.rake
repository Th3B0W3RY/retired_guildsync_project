# frozen_string_literal: true

namespace :infrastructure do
  desc "Upload PostgreSQL custom-format dump to S3 when DATABASE_BACKUP_TO_S3_ENABLED=1 (see DatabaseBackupToS3Service)"
  task database_backup_to_s3: :environment do
    result = DatabaseBackupToS3Service.new.call
    if result[:disabled]
      puts "DatabaseBackupToS3Service: disabled (set DATABASE_BACKUP_TO_S3_ENABLED=1 to run)."
      next
    end
    if result[:ok] && result[:key]
      puts "OK: uploaded key #{result[:key]} (bucket from DATABASE_BACKUP_S3_BUCKET or S3_BUCKET)"
    else
      warn "FAILED: #{result[:error]}"
      exit 1
    end
  end

  desc "Upload gzipped config/schema snapshot to S3 when CONFIG_SNAPSHOT_TO_S3_ENABLED=1 (see ConfigSnapshotToS3Service)"
  task config_snapshot_to_s3: :environment do
    result = ConfigSnapshotToS3Service.new.call
    if result[:disabled]
      puts "ConfigSnapshotToS3Service: disabled (set CONFIG_SNAPSHOT_TO_S3_ENABLED=1 to run)."
      next
    end
    if result[:ok] && result[:key]
      puts "OK: uploaded key #{result[:key]} (bucket from CONFIG_SNAPSHOT_S3_BUCKET or shared backup bucket)"
    else
      warn "FAILED: #{result[:error]}"
      exit 1
    end
  end
end
