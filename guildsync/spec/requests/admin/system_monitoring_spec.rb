# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SystemMonitoring", type: :request do
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

  describe "GET /admin/system-monitoring" do
    it "returns success" do
      get admin_system_monitoring_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.system_monitoring.show.page_title"))
      expect(response.body).to include(I18n.t("admin.system_monitoring.show.refresh"))
      expect(response.body).to include(I18n.t("admin.system_monitoring.show.intro"))
    end

    it "returns frame-only HTML when Turbo-Frame targets main" do
      get admin_system_monitoring_path,
        headers: { "Turbo-Frame" => Admin::SystemMonitoringController::SYSTEM_MONITORING_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::SystemMonitoringController::SYSTEM_MONITORING_MAIN_FRAME}"))
      expect(response.body).to include("data-controller=\"admin-system-monitoring\"")
      expect(response.body).to include(I18n.t("admin.system_monitoring.show.cards.memory"))
      expect(response.body).not_to include(I18n.t("admin.system_monitoring.show.page_title"))
    end

    it "uses manual-only Stimulus dashboard without polling or Chart CDN" do
      get admin_system_monitoring_path
      expect(response.body).to include("data-controller=\"admin-system-monitoring\"")
      expect(response.body).to include("click->admin-system-monitoring#refresh")
      expect(response.body).not_to include("setInterval")
      expect(response.body).not_to include("cdn.jsdelivr.net/npm/chart.js")
    end
  end

  describe "GET /admin/system-monitoring/metrics.json" do
    it "returns JSON with metric keys" do
      get admin_system_monitoring_metrics_path(format: :json)
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/json")
      data = response.parsed_body
      expect(data).to have_key("memory")
      expect(data).to have_key("cpu")
      expect(data).to have_key("disk")
      expect(data).to have_key("sidekiq")
      expect(data).to have_key("puma")
      expect(data).to have_key("database")
      expect(data).to have_key("collected_at")
      expect(data["puma"]).not_to have_key("error")
      expect(data["puma"]["workers"]).to be_a(Integer)
    end
  end

  describe "authentication" do
    before { delete "/admin/logout" }

    it "requires admin for show" do
      get admin_system_monitoring_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for metrics" do
      get admin_system_monitoring_metrics_path(format: :json)
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
