# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin::Dashboard", type: :request do
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

  describe "GET /admin" do
    let!(:user) { create(:user) }
    let!(:guild) { create(:guild, owner: user) }
    let!(:event) { create(:event, guild: guild) }
    let!(:game) { create(:game) }
    let!(:pending_game) { create(:game, active: false, deactivated_at: nil) }

    it "returns frame-only HTML when Turbo-Frame targets main" do
      get "/admin",
        headers: { "Turbo-Frame" => Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME}"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_users"))
      expect(response.body).not_to include(I18n.t("admin.dashboard.title"))
    end

    it "shows dashboard with statistics" do
      get "/admin"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.dashboard.title"))
      expect(response.body).to include("bg-theme-brand-gradient")
      expect(response.body).not_to include("bg-gradient-to-r from-[#4F39F6] to-[#9810FA]")
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_users"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_guilds"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_events"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_games"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.total_alliances"))
      expect(response.body).to include(I18n.t("admin.dashboard.stats.paying_subscribers"))
      # ERB escapes "&" in translated headings (e.g. "Trials & Free" → &amp;).
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.stats.trials_and_free")))
    end

    it "shows total alliances count matching Alliance.count" do
      create_list(:alliance, 2)
      get "/admin"
      expect(response).to have_http_status(:success)
      label = Regexp.escape(I18n.t("admin.dashboard.stats.total_alliances"))
      expect(response.body).to match(
        %r{#{label}</h3>\s*<p class="mt-auto text-3xl font-bold tabular-nums text-white">#{Alliance.count}</p>}
      )
    end

    it "shows only the allowed critical admin feature tiles" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.audit_log.title"))
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.error_tracker.title"))
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.content_moderation.title"))
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.soft_deleted_records.title"))
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.closed_account_recovery.title"))

      expect(response.body).not_to include("System Health")
      expect(response.body).not_to include("Email Logs")
      expect(response.body).not_to include("Feature Flags")
      expect(response.body).not_to include("Danger Zone")
      expect(response.body).not_to include("Delete All Data")
    end

    it "shows System Monitoring and OCR usage links" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.system_monitoring.title"))
      expect(response.body).to include(I18n.t("admin.dashboard.critical_features.ocr_requests.title"))
    end

    it "shows the support pages URL quick action" do
      get "/admin"
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.quick_actions.release_note_link_updater")))
    end

    it "shows the beta features quick action" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.beta_features"))
    end

    it "shows the soft-deleted records quick action" do
      get "/admin"
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.quick_actions.soft_deleted_records")))
    end

    it "shows the database backups quick action" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.database_backups"))
    end

    it "shows the UI Design System quick action" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.ui_design_system"))
    end

    it "shows the Plan card features (pricing) quick action" do
      get "/admin"
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.pricing_plan_features"))
    end

    it "shows the homepage & guest marketing section with CMS links" do
      get "/admin"
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.homepage_cms.title")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.homepage_cms.subtitle")))
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.landing_compare"))
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.user_feedback_manager"))
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.homepage_feature_cards"))
    end

    it "shows pending games alert when there are pending games" do
      get "/admin"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.dashboard.pending_games.title"))
      expect(response.body).to include("1")
    end

    it "does not show pending games alert when there are no pending games" do
      pending_game.update!(active: true)
      get "/admin"
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(I18n.t("admin.dashboard.pending_games.title"))
    end
  end

  describe "Admin authentication required" do
    it "redirects to login if not authenticated" do
      delete "/admin/logout" # Logout first
      get "/admin"
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
