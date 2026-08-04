# frozen_string_literal: true

require "rails_helper"
require "erb"

RSpec.describe "Admin::AuditLogs", type: :request do
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

  describe "GET /admin/audit_logs" do
    let!(:audit_log1) do
      AdminAuditLog.create!(
        admin_email: admin_email,
        action: "approve_game",
        controller: "games",
        record_type: "Game",
        record_id: 1,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    let!(:audit_log2) do
      AdminAuditLog.create!(
        admin_email: "other@test.com",
        action: "delete_user",
        controller: "users",
        record_type: "User",
        record_id: 2,
        ip_address: "127.0.0.1"
      )
    end

    it "lists all audit logs" do
      get admin_audit_logs_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(audit_log1.action)
      expect(response.body).to include(audit_log2.action)
    end

    it "renders index chrome from i18n" do
      get admin_audit_logs_path
      expect(response.body).to include(I18n.t("admin.audit_logs.index.page_title"))
      expect(response.body).to include(I18n.t("admin.audit_logs.index.record_line", type: "Game", id: 1))
    end

    it "renders German index title when locale is de" do
      get admin_audit_logs_path(locale: :de)
      expect(response.body).to include(I18n.t("admin.audit_logs.index.page_title", locale: :de))
    end

    it "filters by admin email" do
      get admin_audit_logs_path, params: { admin_email: admin_email }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(audit_log1.action)
      expect(response.body).not_to include(audit_log2.action)
    end

    it "filters by controller" do
      get admin_audit_logs_path, params: { controller_name: "games" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(audit_log1.action)
      expect(response.body).not_to include(audit_log2.action)
    end

    it "returns frame-only HTML when Turbo-Frame targets results" do
      get admin_audit_logs_path,
        params: { admin_email: admin_email },
        headers: { "Turbo-Frame" => Admin::AuditLogsController::AUDIT_LOGS_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::AuditLogsController::AUDIT_LOGS_RESULTS_FRAME}"))
      expect(response.body).to include(audit_log1.action)
      expect(response.body).not_to include(audit_log2.action)
      expect(response.body).not_to include(I18n.t("admin.audit_logs.index.page_title"))
    end
  end

  describe "GET /admin/audit_logs/:id" do
    let!(:audit_log) do
      AdminAuditLog.create!(
        admin_email: admin_email,
        action: "approve_game",
        controller: "games",
        record_type: "Game",
        record_id: 1,
        changes_data: { active: [false, true] }.to_json,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    it "shows audit log details" do
      get admin_audit_log_path(audit_log)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(audit_log.action)
      expect(response.body).to include(audit_log.admin_email)
      expect(response.body).to include(audit_log.controller)
      expect(response.body).to include(I18n.t("admin.audit_logs.show.page_title"))
      expect(response.body).to include(I18n.t("admin.audit_logs.index.record_line", type: "Game", id: 1))
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get admin_audit_log_path(audit_log),
        headers: { "Turbo-Frame" => Admin::AuditLogsController::AUDIT_LOGS_SHOW_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_audit_logs_show_main"))
      expect(response.body).to include(audit_log.action)
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("admin.audit_logs.show.page_title")))
    end
  end

  describe "GET /admin/audit_logs with filters" do
    let!(:audit_log1) do
      AdminAuditLog.create!(
        admin_email: admin_email,
        action: "approve_game",
        controller: "games",
        record_type: "Game",
        record_id: 1,
        ip_address: "127.0.0.1"
      )
    end

    it "clears filters when Clear link is clicked" do
      # First apply a filter
      get admin_audit_logs_path, params: { admin_email: admin_email }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(audit_log1.action)

      # Then clear filters
      get admin_audit_logs_path
      expect(response).to have_http_status(:success)
      # Should show all logs (both audit_log1 and audit_log2 from earlier tests)
      expect(response.body).to include("approve_game")
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin authentication" do
      get admin_audit_logs_path
      expect(response).to redirect_to(admin_login_path)
    end
  end
end

