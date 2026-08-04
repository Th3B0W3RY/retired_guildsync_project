# frozen_string_literal: true

require "erb"
require "rails_helper"

RSpec.describe "Admin::FlashSettings", type: :request do
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

  describe "GET /admin/settings/flash" do
    it "renders the flash settings page" do
      get "/admin/settings/flash"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.flash_settings.page_title"))
      expect(response.body).to include('id="admin_flash_settings_flash"')
      expect(response.body).to include('id="admin_flash_settings_form_card"')
    end

    it "returns frame-only HTML when Turbo-Frame targets main" do
      get "/admin/settings/flash",
        headers: { "Turbo-Frame" => Admin::FlashSettingsController::FLASH_SETTINGS_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::FlashSettingsController::FLASH_SETTINGS_MAIN_FRAME}"))
      expect(response.body).to include('id="admin_flash_settings_form_card"')
      expect(response.body).not_to include(I18n.t("admin.flash_settings.page_title"))
    end
  end

  describe "PATCH /admin/settings/flash" do
    it "updates the duration" do
      patch "/admin/settings/flash", params: { flash_toast_duration_ms: 3000 }
      expect(response).to redirect_to("/admin/settings/flash")
      expect(SiteSetting.get("flash_toast_duration_ms")).to eq("3000")
    end

    it "rejects out-of-range values" do
      patch "/admin/settings/flash", params: { flash_toast_duration_ms: 100 }
      expect(response).to redirect_to("/admin/settings/flash")
      follow_redirect!
      expect(response.body).to include(SiteSetting::FLASH_TOAST_DURATION_MIN_MS.to_s)
    end

    it "creates an audit log entry" do
      expect {
        patch "/admin/settings/flash", params: { flash_toast_duration_ms: 2500 }
      }.to change(AdminAuditLog, :count).by(1)

      audit = AdminAuditLog.last
      expect(audit.action).to eq("update_flash_toast_duration_ms")
      expect(audit.controller).to eq("flash_settings")
      expect(audit.ip_address).to be_present
    end

    it "returns turbo-stream form refresh and notice on success" do
      patch "/admin/settings/flash",
        params: { flash_toast_duration_ms: 3200 },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_flash_settings_form_card")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.flash_settings.updated"))
      )
      expect(SiteSetting.get("flash_toast_duration_ms")).to eq("3200")
    end

    it "returns turbo-stream alert on invalid duration" do
      patch "/admin/settings/flash",
        params: { flash_toast_duration_ms: "not-a-number" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_flash_settings_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.flash_settings.invalid_duration"))
      )
    end
  end

  describe "POST /admin/settings/flash/test" do
    it "sets a flash and redirects so the toast can render" do
      post "/admin/settings/flash/test", params: { kind: "notice" }
      expect(response).to redirect_to("/admin/settings/flash")
      follow_redirect!
      expect(response.body).to include(I18n.t("admin.flash_settings.test_message.notice"))
    end

    it "returns turbo-stream in-page banner for test notice" do
      post "/admin/settings/flash/test",
        params: { kind: "notice" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_flash_settings_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.flash_settings.test_message.notice"))
      )
    end
  end

  describe "unauthenticated access" do
    it "redirects to admin login" do
      reset!
      get "/admin/settings/flash"
      expect(response).to redirect_to("/admin/login")
    end
  end
end
