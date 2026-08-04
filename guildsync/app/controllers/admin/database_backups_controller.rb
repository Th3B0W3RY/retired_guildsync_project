# frozen_string_literal: true

module Admin
  class DatabaseBackupsController < BaseController
    DATABASE_BACKUPS_MAIN_FRAME = "admin_database_backups_main"

    def show
      load_database_backups_show
      return render("database_backups_show_frame", layout: false) if request.headers["Turbo-Frame"] == DATABASE_BACKUPS_MAIN_FRAME
    end

    private

    def load_database_backups_show
      @backup_feature_enabled = DatabaseBackupToS3Service.enabled?
      @last_success = DatabaseBackupToS3Service.read_last_success
      @config_snapshot_feature_enabled = ConfigSnapshotToS3Service.enabled?
      @config_snapshot_last_success = ConfigSnapshotToS3Service.read_last_success
      @backup_list_continuation = DatabaseBackupToS3Service.sanitize_list_continuation_token_param(params[:continuation_token])
      @config_list_continuation = DatabaseBackupToS3Service.sanitize_list_continuation_token_param(params[:config_continuation_token])
      if @backup_feature_enabled
        @recent_backup_list = DatabaseBackupToS3Service.list_recent_backups(
          max_keys: 100,
          continuation_token: @backup_list_continuation
        )
      end
      if @config_snapshot_feature_enabled
        @recent_config_snapshot_list = ConfigSnapshotToS3Service.list_recent_snapshots(
          max_keys: 100,
          continuation_token: @config_list_continuation
        )
      end
    end
  end
end
