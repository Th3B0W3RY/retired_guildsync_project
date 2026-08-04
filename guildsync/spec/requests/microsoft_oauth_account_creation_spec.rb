# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Microsoft OAuth account creation", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:client_id) { "test_ms_client_id" }
  let(:client_secret) { "test_ms_client_secret" }
  let(:oauth_code) { "test_ms_auth_code" }

  let(:fake_token_response) do
    {
      "access_token" => "fake_ms_access",
      "token_type" => "Bearer",
      "expires_in" => 3600
    }
  end

  let(:fake_profile) do
    {
      "sub" => "microsoft-oidc-sub-888",
      "email" => "msuser@example.com",
      "email_verified" => true
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MICROSOFT_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("MICROSOFT_CLIENT_SECRET").and_return(client_secret)
    allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(nil)

    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:client_id).and_return(client_id)
    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:client_secret).and_return(client_secret)
    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:exchange_code_for_token).and_return(fake_token_response)
    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:user_info).and_return(fake_profile)
  end

  it "completes gated signup when provider email matches verified email" do
    verification = SignupEmailVerification.create!(email: "msuser@example.com")
    token = verification.issue!(ip_address: "127.0.0.1")
    get create_account_verify_path(token: token)
    post create_account_backup_code_path, params: { backup_code_saved: "1" }

    get create_account_choose_method_path
    expect(response.body).to include(I18n.t("account_creation.choose.microsoft.title"))

    post create_account_microsoft_path
    expect(response).to redirect_to(microsoft_login_path(signup: true))

    get "/auth/microsoft", params: { signup: true }
    expect(response.headers["Location"]).to include("login.microsoftonline.com/consumers")
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    user = User.find_by(microsoft_uid: fake_profile["sub"])
    expect(user).to be_present
    expect(user.auth_method).to eq("microsoft")
    expect(user.registration_completed_at).to be_present
  end

  it "accepts Outlook signup when Microsoft userinfo omits email_verified" do
    profile_without_email_verified = fake_profile.except("email_verified")
    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:user_info).and_return(profile_without_email_verified)

    verification = SignupEmailVerification.create!(email: "msuser@example.com")
    token = verification.issue!(ip_address: "127.0.0.1")
    get create_account_verify_path(token: token)
    post create_account_backup_code_path, params: { backup_code_saved: "1" }
    post create_account_microsoft_path
    get "/auth/microsoft", params: { signup: true }
    state = session[:microsoft_oauth_state]

    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    user = User.find_by(microsoft_uid: fake_profile["sub"])
    expect(user).to be_present
    expect(user.auth_method).to eq("microsoft")
    expect(user.registration_completed_at).to be_present
  end

  it "auto-links and signs in an existing verified Outlook email account" do
    user = create(:user,
                  email: "msuser@example.com",
                  username: "existingms",
                  auth_method: :discord,
                  microsoft_uid: nil,
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to be_redirect
    expect(response.location).to include("/auth/microsoft/verify")
    expect(user.reload.microsoft_uid).to eq(fake_profile["sub"])
    expect(user.auth_method).to eq("microsoft")
    expect(session["warden.user.user.key"]).to be_present
  end

  it "rejects sign-in when the linked Outlook account is archived" do
    user = create(:user,
                  email: "archived-linked-ms@example.com",
                  username: "archivedlinkedms",
                  auth_method: :microsoft,
                  microsoft_uid: fake_profile["sub"],
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current,
                  archived: true)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.microsoft_uid).to eq(fake_profile["sub"])
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when the existing email account has a different Microsoft identity" do
    user = create(:user,
                  email: "msuser@example.com",
                  username: "conflictingms",
                  auth_method: :microsoft,
                  microsoft_uid: "different-ms-sub",
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.microsoft_uid).to eq("different-ms-sub")
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when the matching email account is not complete and verified" do
    user = create(:user,
                  email: "msuser@example.com",
                  username: "incompletems",
                  auth_method: :mfa,
                  microsoft_uid: nil,
                  registration_completed_at: nil,
                  confirmed_at: nil,
                  signup_email_verified_at: nil)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.microsoft_uid).to be_nil
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when Microsoft userinfo omits email during login" do
    profile_without_email = fake_profile.except("email")
    allow_any_instance_of(MicrosoftUserOAuthService).to receive(:user_info).and_return(profile_without_email)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
  end

  it "rejects auto-link when the matching Outlook email account is archived" do
    user = create(:user,
                  email: "msuser@example.com",
                  username: "archivedms",
                  auth_method: :discord,
                  microsoft_uid: nil,
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current,
                  archived: true)

    get "/auth/microsoft"
    state = session[:microsoft_oauth_state]
    get "/auth/microsoft/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.microsoft_uid).to be_nil
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "redirects to login when OAuth state does not match session" do
    get "/auth/microsoft"
    get "/auth/microsoft/callback", params: { code: oauth_code, state: "tampered" }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.invalid_state"))
  end

  it "shows Outlook sign-in on the login page" do
    get login_path

    expect(response.body).to include(I18n.t("sessions.new.sign_in_with_microsoft"))
  end
end
