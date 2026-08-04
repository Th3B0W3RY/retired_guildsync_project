# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account settings auth method labels", type: :request do
  describe "GET /account/settings" do
    it "shows Using MFA when MFA is the active sign-in method" do
      user = create(:user, :with_mfa, auth_method: "mfa", email: "mfa_settings_spec@example.com")
      User.skip_mfa_verification_flags[user.id] = true
      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa.button_active"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.discord.button"))
    end

    it "shows Using Discord when Discord is the active sign-in method" do
      user = create(:user, auth_method: "discord", discord_user_id: "123", discord_username: "tester", discord_connected: true)
      user.create_user_discord_connection!(discord_user_id: "123", access_token: "tok", scopes: "identify")

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa.button"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.discord.button_active"))
    end

    it "shows Using Gmail when Google is the active sign-in method" do
      user = create(:user, auth_method: :google, google_uid: "google-settings-spec-sub", email: "google_settings_spec@example.com")

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.google.active"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa.button"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.discord.button"))
    end

    it "shows Using Outlook when Microsoft is the active sign-in method" do
      user = create(:user, auth_method: :microsoft, microsoft_uid: "ms-settings-spec-sub", email: "microsoft_settings_spec@example.com")

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.microsoft.active"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa.button"))
      expect(response.body).to include(I18n.t("settings.account.auth_method.discord.button"))
    end

    it "shows MFA backup warning when Google is primary and MFA is not enabled" do
      user = create(
        :user,
        auth_method: :google,
        google_uid: "google-backup-hint-sub",
        mfa_enabled: false,
        email: "google_backup_hint_spec@example.com"
      )

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa_backup_warning"))
    end

    it "does not show MFA backup warning when Google is primary but MFA is enabled" do
      user = create(
        :user,
        :with_mfa,
        auth_method: :google,
        google_uid: "google-mfa-enabled-sub",
        email: "google_mfa_enabled_spec@example.com"
      )
      User.skip_mfa_verification_flags[user.id] = true

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(I18n.t("settings.account.auth_method.mfa_backup_warning"))
    end

    it "shows MFA backup warning when Discord is primary and MFA is not enabled" do
      user = create(
        :user,
        auth_method: "discord",
        discord_user_id: "backup-hint-discord",
        discord_username: "backup_hint",
        discord_connected: true,
        mfa_enabled: false,
        email: "discord_backup_hint_spec@example.com"
      )
      user.create_user_discord_connection!(discord_user_id: "backup-hint-discord", access_token: "tok", scopes: "identify")

      sign_in user

      get account_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.account.auth_method.mfa_backup_warning"))
    end

    describe "support_center_url in member chrome" do
      let(:settings_user) do
        u = create(:user, auth_method: "discord", discord_user_id: "456", discord_username: "support_link_user", discord_connected: true)
        u.create_user_discord_connection!(discord_user_id: "456", access_token: "tok", scopes: "identify")
        u
      end
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      before do
        sign_in settings_user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "includes default support URL in HTML" do
        get account_settings_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get account_settings_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://account-settings-support.example/help")
        get account_settings_path
        expect(response.body).to include("https://account-settings-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://account-settings-support.example/help")
        get account_settings_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://account-settings-support.example/help")
      end

      it "uses the support pages route for account deletion support copy" do
        allow(AccountDeletion).to receive(:feature_enabled?).and_return(true)

        get account_settings_path

        expect(response.body).to include(%(href="#{contact_support_path}"))
        expect(response.body).not_to include(%(href="#{footer_support_contact_path}"))
      end
    end
  end
end
