# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Google OAuth account creation", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:client_id) { "test_google_client_id" }
  let(:client_secret) { "test_google_client_secret" }
  let(:oauth_code) { "test_google_auth_code" }

  let(:fake_token_response) do
    {
      "access_token" => "fake_google_access",
      "token_type" => "Bearer",
      "expires_in" => 3600
    }
  end

  let(:fake_profile) do
    {
      "sub" => "google-oidc-sub-999",
      "email" => "googleuser@example.com",
      "email_verified" => true
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return(client_secret)
    allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(nil)

    allow_any_instance_of(GoogleUserOAuthService).to receive(:client_id).and_return(client_id)
    allow_any_instance_of(GoogleUserOAuthService).to receive(:client_secret).and_return(client_secret)
    allow_any_instance_of(GoogleUserOAuthService).to receive(:exchange_code_for_token).and_return(fake_token_response)
    allow_any_instance_of(GoogleUserOAuthService).to receive(:user_info).and_return(fake_profile)
  end

  it "completes gated signup when provider email matches verified email" do
    verification = SignupEmailVerification.create!(email: "googleuser@example.com")
    token = verification.issue!(ip_address: "127.0.0.1")
    get create_account_verify_path(token: token)
    expect(response).to redirect_to(create_account_backup_code_path)

    post create_account_backup_code_path, params: { backup_code_saved: "1" }
    expect(response).to redirect_to(create_account_choose_method_path)

    get create_account_choose_method_path
    expect(response.body).to include(I18n.t("account_creation.choose.google.title"))

    post create_account_google_path
    expect(response).to redirect_to(google_login_path(signup: true))

    get "/auth/google", params: { signup: true }
    expect(response).to have_http_status(:redirect)
    expect(response.headers["Location"]).to include("accounts.google.com")
    expect(session[:google_oauth_from]).to eq("signup")

    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to be_redirect
    expect(response.location).to include("/auth/google/verify")

    user = User.find_by(google_uid: fake_profile["sub"])
    expect(user).to be_present
    expect(user.email).to eq("googleuser@example.com")
    expect(user.auth_method).to eq("google")
    expect(user.registration_completed_at).to be_present
  end

  it "rejects signup when provider email does not match" do
    verification = SignupEmailVerification.create!(email: "other@example.com")
    token = verification.issue!(ip_address: "127.0.0.1")
    get create_account_verify_path(token: token)
    post create_account_backup_code_path, params: { backup_code_saved: "1" }
    post create_account_google_path
    get "/auth/google", params: { signup: true }
    state = session[:google_oauth_state]

    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(create_account_choose_method_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.email_mismatch"))
    expect(User.find_by(email: "other@example.com").registration_completed_at).to be_nil
  end

  it "rejects signup when Google does not report the email as verified" do
    unverified_profile = fake_profile.merge("email_verified" => false)
    allow_any_instance_of(GoogleUserOAuthService).to receive(:user_info).and_return(unverified_profile)

    verification = SignupEmailVerification.create!(email: "googleuser@example.com")
    token = verification.issue!(ip_address: "127.0.0.1")
    get create_account_verify_path(token: token)
    post create_account_backup_code_path, params: { backup_code_saved: "1" }
    post create_account_google_path
    get "/auth/google", params: { signup: true }
    state = session[:google_oauth_state]

    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(create_account_choose_method_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.email_not_verified"))
    expect(User.find_by(email: "googleuser@example.com").registration_completed_at).to be_nil
  end

  it "redirects to login when OAuth state does not match session" do
    get "/auth/google"
    get "/auth/google/callback", params: { code: oauth_code, state: "tampered" }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.invalid_state"))
  end

  it "logs in an existing Google-linked user" do
    create(:user,
           email: "existingg@example.com",
           username: "existingg",
           google_uid: fake_profile["sub"],
           auth_method: :google,
           registration_completed_at: Time.current,
           confirmed_at: Time.current,
           signup_email_verified_at: Time.current)

    get login_path
    expect(response.body).to include(I18n.t("sessions.new.sign_in_with_google"))

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to be_redirect
    expect(response.location).to include("/auth/google/verify")
    warden_data = session["warden.user.user.key"]
    expect(warden_data).to be_present
  end

  it "auto-links and signs in an existing verified Google email account" do
    user = create(:user,
                  email: "googleuser@example.com",
                  username: "existinggoogle",
                  auth_method: :discord,
                  google_uid: nil,
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current)

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to be_redirect
    expect(response.location).to include("/auth/google/verify")
    expect(user.reload.google_uid).to eq(fake_profile["sub"])
    expect(user.auth_method).to eq("google")
    expect(session["warden.user.user.key"]).to be_present
  end

  it "rejects sign-in when the linked Google account is archived" do
    user = create(:user,
                  email: "archived-linked-google@example.com",
                  username: "archivedlinkedgoogle",
                  auth_method: :google,
                  google_uid: fake_profile["sub"],
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current,
                  archived: true)

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.google_uid).to eq(fake_profile["sub"])
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when the existing email account has a different Google identity" do
    user = create(:user,
                  email: "googleuser@example.com",
                  username: "conflictinggoogle",
                  auth_method: :google,
                  google_uid: "different-google-sub",
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current)

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.google_uid).to eq("different-google-sub")
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when Google does not report the email as verified during login" do
    user = create(:user,
                  email: "googleuser@example.com",
                  username: "unverifiedgoogle",
                  auth_method: :discord,
                  google_uid: nil,
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current)
    unverified_profile = fake_profile.merge("email_verified" => false)
    allow_any_instance_of(GoogleUserOAuthService).to receive(:user_info).and_return(unverified_profile)

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.google_uid).to be_nil
    expect(session["warden.user.user.key"]).to be_blank
  end

  it "rejects auto-link when the matching Google email account is archived" do
    user = create(:user,
                  email: "googleuser@example.com",
                  username: "archivedgoogle",
                  auth_method: :discord,
                  google_uid: nil,
                  registration_completed_at: Time.current,
                  confirmed_at: Time.current,
                  signup_email_verified_at: Time.current,
                  archived: true)

    get "/auth/google"
    state = session[:google_oauth_state]
    get "/auth/google/callback", params: { code: oauth_code, state: state }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.oidc_user_auth.no_account"))
    expect(user.reload.google_uid).to be_nil
    expect(session["warden.user.user.key"]).to be_blank
  end
end
