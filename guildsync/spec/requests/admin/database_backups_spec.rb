# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::DatabaseBackupsController", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/database-backups" do
    before do
      allow(ConfigSnapshotToS3Service).to receive(:enabled?).and_return(false)
      allow(ConfigSnapshotToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:list_recent_snapshots).and_return(
        ConfigSnapshotToS3Service::RecentConfigSnapshotList.new(
          entries: [], truncated: false, failed: false, next_continuation_token: nil
        )
      )
    end

    it "returns success" do
      get admin_database_backups_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.database_backups.title"))
      expect(response.body).to include(I18n.t("admin.database_backups.config_snapshot_heading"))
    end

    it "returns frame-only HTML when Turbo-Frame targets main" do
      get admin_database_backups_path,
        headers: { "Turbo-Frame" => Admin::DatabaseBackupsController::DATABASE_BACKUPS_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::DatabaseBackupsController::DATABASE_BACKUPS_MAIN_FRAME}"))
      expect(response.body).to include(I18n.t("admin.database_backups.last_success"))
      expect(response.body).not_to include(I18n.t("admin.database_backups.title"))
    end

    it "shows none_yet when cache empty" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      get admin_database_backups_path
      expect(response.body).to include(I18n.t("admin.database_backups.none_yet"))
    end

    it "shows last s3 key when cache populated" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(
        { "s3_key" => "database_backups/guildsync-spec.dump", "finished_at" => "2026-04-02T12:00:00Z" }
      )
      get admin_database_backups_path
      expect(response.body).to include("database_backups/guildsync-spec.dump")
      expect(response.body).to include("2026-04-02T12:00:00Z")
    end

    it "shows recent objects table when backup enabled and list returns entries" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(true)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      list = DatabaseBackupToS3Service::RecentBackupList.new(
        entries: [ { key: "database_backups/guildsync-listed.dump", size: 2048, last_modified: "2026-04-02T15:00:00.000Z" } ],
        truncated: false,
        failed: false,
        next_continuation_token: nil
      )
      allow(DatabaseBackupToS3Service).to receive(:list_recent_backups).and_return(list)
      get admin_database_backups_path
      expect(response.body).to include(I18n.t("admin.database_backups.recent_heading"))
      expect(response.body).to include("database_backups/guildsync-listed.dump")
    end

    it "does not render recent-objects section when backup feature is off" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(false)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      get admin_database_backups_path
      expect(response.body).not_to include(I18n.t("admin.database_backups.recent_heading"))
    end

    it "passes sanitized continuation_token to list_recent_backups" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(true)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      empty = DatabaseBackupToS3Service::RecentBackupList.new(
        entries: [], truncated: false, failed: false, next_continuation_token: nil
      )
      expect(DatabaseBackupToS3Service).to receive(:list_recent_backups).with(
        max_keys: 100,
        continuation_token: "page2token"
      ).and_return(empty)
      get admin_database_backups_path(continuation_token: "page2token")
      expect(response).to have_http_status(:success)
    end

    it "shows next page and first page links when list is truncated" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(true)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      list = DatabaseBackupToS3Service::RecentBackupList.new(
        entries: [ { key: "database_backups/a.dump", size: 1, last_modified: "2026-01-01T00:00:00.000Z" } ],
        truncated: true,
        failed: false,
        next_continuation_token: "next-s3-token"
      )
      allow(DatabaseBackupToS3Service).to receive(:list_recent_backups).and_return(list)
      get admin_database_backups_path(continuation_token: "prev-page-token")
      expect(response.body).to include(I18n.t("admin.database_backups.recent_next_page"))
      expect(response.body).to include("next-s3-token")
      expect(response.body).to include(I18n.t("admin.database_backups.recent_first_page"))
    end

    it "drops oversized continuation_token" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(true)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      empty = DatabaseBackupToS3Service::RecentBackupList.new(
        entries: [], truncated: false, failed: false, next_continuation_token: nil
      )
      expect(DatabaseBackupToS3Service).to receive(:list_recent_backups).with(
        max_keys: 100,
        continuation_token: nil
      ).and_return(empty)
      get admin_database_backups_path(continuation_token: "x" * 9000)
      expect(response).to have_http_status(:success)
    end

    it "shows config snapshot feature_off banner when snapshot disabled" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      get admin_database_backups_path
      expect(response.body).to include(I18n.t("admin.database_backups.config_snapshot_feature_off"))
    end

    it "shows config snapshot key when cache populated" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:read_last_success).and_return(
        { "s3_key" => "config_snapshots/guildsync-config-spec.tar.gz", "finished_at" => "2026-04-02T18:00:00Z" }
      )
      get admin_database_backups_path
      expect(response.body).to include("config_snapshots/guildsync-config-spec.tar.gz")
      expect(response.body).to include("2026-04-02T18:00:00Z")
    end

    it "shows config_snapshot_none_yet when snapshot enabled but cache empty" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:enabled?).and_return(true)
      allow(ConfigSnapshotToS3Service).to receive(:read_last_success).and_return(nil)
      get admin_database_backups_path
      expect(response.body).to include(I18n.t("admin.database_backups.config_snapshot_none_yet"))
      expect(response.body).not_to include(I18n.t("admin.database_backups.config_snapshot_feature_off"))
    end

    it "passes sanitized config_continuation_token to list_recent_snapshots" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:enabled?).and_return(true)
      empty = ConfigSnapshotToS3Service::RecentConfigSnapshotList.new(
        entries: [], truncated: false, failed: false, next_continuation_token: nil
      )
      expect(ConfigSnapshotToS3Service).to receive(:list_recent_snapshots).with(
        max_keys: 100,
        continuation_token: "cfg-page-2"
      ).and_return(empty)
      get admin_database_backups_path(config_continuation_token: "cfg-page-2")
      expect(response).to have_http_status(:success)
    end

    it "shows config snapshot object table when list returns entries" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:enabled?).and_return(true)
      list = ConfigSnapshotToS3Service::RecentConfigSnapshotList.new(
        entries: [ { key: "config_snapshots/guildsync-config-listed.tar.gz", size: 512, last_modified: "2026-04-02T20:00:00.000Z" } ],
        truncated: false,
        failed: false,
        next_continuation_token: nil
      )
      allow(ConfigSnapshotToS3Service).to receive(:list_recent_snapshots).and_return(list)
      get admin_database_backups_path
      expect(response.body).to include(I18n.t("admin.database_backups.config_recent_heading"))
      expect(response.body).to include("config_snapshots/guildsync-config-listed.tar.gz")
    end

    it "drops oversized config_continuation_token" do
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      allow(ConfigSnapshotToS3Service).to receive(:enabled?).and_return(true)
      empty = ConfigSnapshotToS3Service::RecentConfigSnapshotList.new(
        entries: [], truncated: false, failed: false, next_continuation_token: nil
      )
      expect(ConfigSnapshotToS3Service).to receive(:list_recent_snapshots).with(
        max_keys: 100,
        continuation_token: nil
      ).and_return(empty)
      get admin_database_backups_path(config_continuation_token: "y" * 9000)
      expect(response).to have_http_status(:success)
    end

    it "includes config_continuation_token in DB next page link when both lists paginated" do
      allow(DatabaseBackupToS3Service).to receive(:enabled?).and_return(true)
      allow(DatabaseBackupToS3Service).to receive(:read_last_success).and_return(nil)
      db_list = DatabaseBackupToS3Service::RecentBackupList.new(
        entries: [ { key: "database_backups/a.dump", size: 1, last_modified: "2026-01-01T00:00:00.000Z" } ],
        truncated: true,
        failed: false,
        next_continuation_token: "db-next"
      )
      allow(DatabaseBackupToS3Service).to receive(:list_recent_backups).and_return(db_list)
      get admin_database_backups_path(config_continuation_token: "cfg-stay")
      expect(response.body).to include("config_continuation_token=cfg-stay")
      expect(response.body).to include("continuation_token=db-next")
    end
  end

  describe "authentication" do
    before { delete "/admin/logout" }

    it "requires admin" do
      get admin_database_backups_path
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
