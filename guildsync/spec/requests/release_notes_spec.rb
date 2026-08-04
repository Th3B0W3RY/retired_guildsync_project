# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Release Notes", type: :request do
  let(:default_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  describe "GET /release-notes" do
    it "redirects to the default release notes URL" do
      get "/release-notes"
      expect(response).to redirect_to(default_url)
    end

    it "redirects to the default release notes URL on mobile User-Agent" do
      get "/release-notes", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to redirect_to(default_url)
    end

    it "redirects to an admin-configured URL when set" do
      SiteSetting.set("release_notes_url", "https://example.com/custom-notes")
      get "/release-notes"
      expect(response).to redirect_to("https://example.com/custom-notes")
    end

    it "redirects to an admin-configured URL when set (mobile User-Agent)" do
      SiteSetting.set("release_notes_url", "https://example.com/custom-notes")
      get "/release-notes", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to redirect_to("https://example.com/custom-notes")
    end
  end

  describe "GET /support/contact" do
    def sign_in_discord_user_with_mfa_stub
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    context "when not signed in" do
      it "redirects without exposing the default external support host" do
        get contact_support_path
        expect(response).to have_http_status(:redirect)
        expect(response.location).not_to include(URI.parse(default_url).host)
      end

      it "redirects without exposing the default external support host (mobile User-Agent)" do
        get contact_support_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:redirect)
        expect(response.location).not_to include(URI.parse(default_url).host)
      end

      it "redirects without exposing a configured custom support host" do
        SiteSetting.set("release_notes_url", "https://support-custom.test/help")
        get contact_support_path
        expect(response).to have_http_status(:redirect)
        expect(response.location).not_to include("support-custom.test")
      end

      it "redirects without exposing a configured custom support host (mobile User-Agent)" do
        SiteSetting.set("release_notes_url", "https://support-custom.test/help")
        get contact_support_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:redirect)
        expect(response.location).not_to include("support-custom.test")
      end
    end

    it "redirects to the default support URL when signed in" do
      sign_in_discord_user_with_mfa_stub
      get contact_support_path
      expect(response).to redirect_to(default_url)
    end

    it "redirects to the default support URL when signed in (mobile User-Agent)" do
      sign_in_discord_user_with_mfa_stub
      get contact_support_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to redirect_to(default_url)
    end

    it "redirects to an admin-configured support URL when signed in" do
      SiteSetting.set("release_notes_url", "https://example.com/custom-notes")
      sign_in_discord_user_with_mfa_stub
      get contact_support_path
      expect(response).to redirect_to("https://example.com/custom-notes")
    end

    it "redirects to an admin-configured support URL when signed in (mobile User-Agent)" do
      SiteSetting.set("release_notes_url", "https://example.com/custom-notes")
      sign_in_discord_user_with_mfa_stub
      get contact_support_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to redirect_to("https://example.com/custom-notes")
    end
  end

  describe "Release Notes links in app" do
    it "dropdown link points to the configured URL when signed in" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      get "/dashboard"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_url)
    end

    it "roadmap guest page shows title and guest footer (release notes link is signed-in only in roadmap UI)" do
      get "/roadmap"
      expect(response).to have_http_status(:success)
      # Title is HTML-escaped in the template (&amp;)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("roadmap.title")))
      expect(response.body).to include(I18n.t("roadmap.guest_footer_note"))
    end

    it "roadmap guest page on mobile variant shows escaped title and guest footer" do
      get "/roadmap", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("roadmap.title")))
      expect(response.body).to include(I18n.t("roadmap.guest_footer_note"))
    end

    it "sidebar Contact Support link points to the configured URL" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      SiteSetting.set("release_notes_url", "https://custom-support.example.com")
      get "/dashboard"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("https://custom-support.example.com")
    end

    it "dropdown shows release notes label and instructions from i18n" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      get "/dashboard"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("layouts.application.dropdown.release_notes"))
      # ERB escapes `>` in the hint line as &gt; inside the avatar dropdown <p>.
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("layouts.application.dropdown.release_notes_instructions"))
      )
    end

    it "mobile HTML variant dashboard includes the same release notes dropdown i18n" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get "/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("layouts.application.dropdown.release_notes"))
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("layouts.application.dropdown.release_notes_instructions"))
      )
    end

    it "mobile HTML variant dashboard surfaces default support URL in signed-in shell" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get "/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_url)
    end

    it "mobile HTML variant dashboard sidebar uses configured support URL" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      SiteSetting.set("release_notes_url", "https://custom-support.example.com")

      get "/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("https://custom-support.example.com")
    end
  end
end
