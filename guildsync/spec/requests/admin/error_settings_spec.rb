# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ErrorSettings", type: :request do
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

  describe "GET /admin/settings/error-notifications" do
    it "renders the page with the current cadence and severity checkboxes" do
      SiteSetting.set("error_batch_cadence_hours", "12")
      SiteSetting.set("error_immediate_severities", '["urgent","high"]')

      get admin_error_notification_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.error_settings.show.page_title"))
      expect(response.body).to include("12")                # current cadence value
      expect(response.body).to include("urgent")            # severity checkbox labels
      expect(response.body).to include("high")
    end

    it "requires admin authentication" do
      delete "/admin/logout"
      get admin_error_notification_settings_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  describe "PATCH /admin/settings/error-notifications" do
    it "saves the new cadence and immediate severities, and creates an audit log entry" do
      expect {
        patch admin_update_error_notification_settings_path, params: {
          error_batch_cadence_hours: 48,
          error_immediate_severities: ["urgent"]
        }
      }.to change(AdminAuditLog, :count).by(1)

      expect(SiteSetting.error_batch_cadence_hours).to eq(48)
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
      expect(response).to redirect_to(admin_error_notification_settings_path)
      expect(flash[:notice]).to eq(I18n.t("admin.error_settings.flash.updated"))

      audit = AdminAuditLog.last
      expect(audit.action).to eq("update_error_notification_settings")
      expect(audit.admin_email).to eq(admin_email)
    end

    it "rejects a cadence below the minimum and does not update the setting" do
      original = SiteSetting.error_batch_cadence_hours
      patch admin_update_error_notification_settings_path, params: {
        error_batch_cadence_hours: 0
      }
      expect(SiteSetting.error_batch_cadence_hours).to eq(original)
      expect(response).to redirect_to(admin_error_notification_settings_path)
      expect(flash[:alert]).to include(SiteSetting::ERROR_BATCH_CADENCE_MIN.to_s)
    end

    it "accepts an empty immediate-severities list (all errors go to batch)" do
      patch admin_update_error_notification_settings_path, params: {
        error_batch_cadence_hours: 24
        # omitting error_immediate_severities — browser sends nothing when no checkboxes checked
      }
      expect(response).to redirect_to(admin_error_notification_settings_path)
      expect(SiteSetting.error_immediate_severities).to eq([])
    end
  end
end
