# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ErrorBatchReports", type: :request do
  let(:admin_email)    { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"]    = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/error-batch-reports" do
    it "renders the index listing existing reports" do
      report = create(:error_batch_report, :with_errors, triggered_by: "scheduled")

      get admin_error_batch_reports_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.error_batch_reports.index.page_title"))
      expect(response.body).to include(report.period_end.strftime("%Y-%m-%d"))
    end

    it "shows the empty-state message when no reports exist" do
      get admin_error_batch_reports_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.error_batch_reports.index.empty"))
    end

    it "requires admin authentication" do
      delete "/admin/logout"
      get admin_error_batch_reports_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  describe "GET /admin/error-batch-reports/:id" do
    let!(:report) { create(:error_batch_report, :with_errors) }

    it "renders the report detail page with cluster information" do
      get admin_error_batch_report_path(report)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.error_batch_reports.show.page_title"))
      expect(response.body).to include(report.total_errors.to_s)
      expect(response.body).to include("StandardError")   # from :with_errors factory
    end
  end

  describe "POST /admin/error-batch-reports/run_now" do
    it "enqueues ErrorBatchReportJob with the admin email as triggered_by" do
      expect(ErrorBatchReportJob).to receive(:perform_later).with("admin:#{admin_email}")
      post run_now_admin_error_batch_reports_path
    end

    it "redirects to the reports index with a queued notice" do
      allow(ErrorBatchReportJob).to receive(:perform_later)
      post run_now_admin_error_batch_reports_path
      expect(response).to redirect_to(admin_error_batch_reports_path)
      expect(flash[:notice]).to eq(I18n.t("admin.error_batch_reports.flash.queued"))
    end

    it "creates an audit log entry" do
      allow(ErrorBatchReportJob).to receive(:perform_later)
      expect {
        post run_now_admin_error_batch_reports_path
      }.to change(AdminAuditLog, :count).by(1)
      expect(AdminAuditLog.last.action).to eq("trigger_error_batch_report")
    end

    it "requires admin authentication" do
      delete "/admin/logout"
      post run_now_admin_error_batch_reports_path
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
