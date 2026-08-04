# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile settings (GET /profile/settings)", type: :request do
  describe "support_center_url in member chrome" do
    let(:user) do
      u = create(:user, auth_method: "discord", discord_user_id: "789", discord_username: "profile_settings_user", discord_connected: true)
      u.create_user_discord_connection!(discord_user_id: "789", access_token: "tok", scopes: "identify")
      u
    end
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    before do
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "includes default support URL in HTML" do
      get profile_settings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get profile_settings_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://profile-settings-support.example/help")
      get profile_settings_path
      expect(response.body).to include("https://profile-settings-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://profile-settings-support.example/help")
      get profile_settings_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://profile-settings-support.example/help")
    end
  end
end
