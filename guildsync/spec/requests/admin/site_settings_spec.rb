# frozen_string_literal: true

require "rails_helper"
require "erb"

RSpec.describe "Admin::SiteSettings", type: :request do
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

  describe "GET /admin/settings/release-notes" do
    it "renders the release notes settings page" do
      get "/admin/settings/release-notes"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("roadmap.admin.release_notes.title")))
    end

    it "shows the current URL" do
      SiteSetting.set("release_notes_url", "https://example.com/notes")
      get "/admin/settings/release-notes"
      expect(response.body).to include("https://example.com/notes")
    end

    it "shows the default URL when none is configured" do
      get "/admin/settings/release-notes"
      expect(response.body).to include(SiteSetting::DEFAULTS["release_notes_url"])
    end

    it "labels the setting as the URL for support pages" do
      get "/admin/settings/release-notes"

      expect(response.body).to include(ERB::Util.html_escape("URL For Support Pages"))
      expect(response.body).to include("Support pages URL")
    end

    it "does not overwrite an existing database value when rendering the page" do
      SiteSetting.set("release_notes_url", "https://persistent-support.example/help")

      expect {
        get "/admin/settings/release-notes"
      }.not_to change { SiteSetting.release_notes_url }

      expect(response.body).to include("https://persistent-support.example/help")
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get "/admin/settings/release-notes",
        headers: { "Turbo-Frame" => Admin::SiteSettingsController::RELEASE_NOTES_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_release_notes_main"))
      expect(response.body).to include("release_notes_url")
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("roadmap.admin.release_notes.title")))
    end
  end

  describe "PATCH /admin/settings/release-notes" do
    it "updates the support pages URL" do
      patch "/admin/settings/release-notes", params: { release_notes_url: "https://new-site.com/release-notes" }
      expect(response).to redirect_to("/admin/settings/release-notes")
      follow_redirect!
      expect(response.body).to include("https://new-site.com/release-notes")
      expect(SiteSetting.release_notes_url).to eq("https://new-site.com/release-notes")
    end

    it "rejects blank URLs" do
      patch "/admin/settings/release-notes", params: { release_notes_url: "" }
      expect(response).to redirect_to("/admin/settings/release-notes")
      follow_redirect!
      expect(response.body).to include("valid URL")
    end

    it "rejects non-HTTP URLs" do
      patch "/admin/settings/release-notes", params: { release_notes_url: "ftp://bad.com" }
      expect(response).to redirect_to("/admin/settings/release-notes")
      follow_redirect!
      expect(response.body).to include("valid URL")
    end

    it "rejects malformed HTTP URLs without changing the saved support pages URL" do
      SiteSetting.set("release_notes_url", "https://existing-support.example/help")

      expect {
        patch "/admin/settings/release-notes", params: { release_notes_url: "https:///missing-host" }
      }.not_to change { SiteSetting.release_notes_url }

      expect(response).to redirect_to("/admin/settings/release-notes")
      follow_redirect!
      expect(response.body).to include("valid URL")
    end

    it "rejects URLs with response-splitting characters" do
      SiteSetting.set("release_notes_url", "https://existing-support.example/help")

      expect {
        patch "/admin/settings/release-notes", params: { release_notes_url: "https://support.example/\nLocation: https://evil.example" }
      }.not_to change { SiteSetting.release_notes_url }

      expect(response).to redirect_to("/admin/settings/release-notes")
    end

    it "creates an audit log entry" do
      expect {
        patch "/admin/settings/release-notes", params: { release_notes_url: "https://new-site.com/notes" }
      }.to change(AdminAuditLog, :count).by(1)

      log = AdminAuditLog.last
      expect(log.action).to eq("update_release_notes_url")
      expect(log.controller).to eq("site_settings")
      expect(log.admin_email).to eq(admin_email)
      expect(log.ip_address).to be_present
    end

    it "returns turbo_stream refresh on successful update" do
      patch "/admin/settings/release-notes",
        params: { release_notes_url: "https://turbo-notes.example/releases" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="update"', "admin_release_notes_flash")
      expect(response.body).to include('action="replace"', "admin_release_notes_form_wrap")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("roadmap.admin.release_notes.updated"))
      )
      expect(response.body).to include("https://turbo-notes.example/releases")
      expect(SiteSetting.release_notes_url).to eq("https://turbo-notes.example/releases")
    end

    it "returns see_other redirect for invalid URL when Accept is turbo_stream" do
      patch "/admin/settings/release-notes",
        params: { release_notes_url: "ftp://bad.com" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/admin/settings/release-notes")
    end
  end

  describe "unauthenticated access" do
    it "redirects to admin login" do
      reset!
      get "/admin/settings/release-notes"
      expect(response).to redirect_to("/admin/login")
    end
  end
end
