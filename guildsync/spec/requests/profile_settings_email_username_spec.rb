# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile settings email, username, and verified-email enforcement", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def sign_in_discord_placeholder_user!(user)
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "EnsureVerifiedRealEmail" do
    let(:user) do
      create(:user,
        auth_method: :discord,
        email: "placeholder_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))
    end

    before { sign_in_discord_placeholder_user!(user) }

    it "redirects dashboard to profile settings with notice" do
      get dashboard_path
      expect(response).to redirect_to(profile_settings_path)
      expect(flash[:alert]).to eq(I18n.t("settings.profile.email_verification.required_notice"))
    end

    it "allows profile settings" do
      get profile_settings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("settings.profile.email_verification.banner_title"))
    end

    it "allows verified users to load dashboard" do
      user.update_columns(
        email: "verified_#{SecureRandom.hex(4)}@example.com",
        signup_email_verified_at: Time.current,
        updated_at: Time.current
      )
      get dashboard_path
      expect(response).not_to redirect_to(profile_settings_path)
    end
  end

  describe "PATCH /profile/settings/username" do
    let(:user) do
      create(:user, :discord_auth,
        email: "member_#{SecureRandom.hex(4)}@example.com",
        signup_email_verified_at: Time.current,
        discord_user_id: SecureRandom.hex(8))
    end

    before { sign_in_discord_placeholder_user!(user) }

    it "updates username" do
      new_name = "u#{SecureRandom.hex(5)}"
      patch profile_settings_username_path, params: { user: { username: new_name } }

      expect(response).to redirect_to(profile_settings_path)
      expect(user.reload.username).to eq(new_name)
    end

    it "rejects invalid username" do
      patch profile_settings_username_path, params: { user: { username: "ab" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /profile/settings/email_verification" do
    let(:user) do
      create(:user,
        auth_method: :discord,
        email: "ph_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))
    end

    before { sign_in_discord_placeholder_user!(user) }

    it "creates verification and enqueues mail" do
      expect {
        post profile_settings_email_verification_path, params: { email: "newmail_#{SecureRandom.hex(4)}@example.com" }
      }.to change(SignupEmailVerification, :count).by(1)
        .and change(enqueued_jobs, :size).by(1)

      expect(response).to redirect_to(profile_settings_path)
      v = SignupEmailVerification.last
      expect(v.user_id).to eq(user.id)
    end

    it "rejects taken email" do
      email = "taken-#{SecureRandom.hex(4)}@example.com"
      create(:user, email: email)
      post profile_settings_email_verification_path, params: { email: email }
      expect(response).to redirect_to(profile_settings_path)
      expect(flash[:alert]).to eq(I18n.t("settings.profile.email.taken"))
    end

    it "reuses the same pending verification row when requesting a second email" do
      first_email = "first-#{SecureRandom.hex(4)}@example.com"
      second_email = "second-#{SecureRandom.hex(4)}@example.com"

      post profile_settings_email_verification_path, params: { email: first_email }
      expect(response).to redirect_to(profile_settings_path)
      v = SignupEmailVerification.unverified.find_by!(user_id: user.id)
      first_id = v.id

      post profile_settings_email_verification_path, params: { email: second_email }
      expect(response).to redirect_to(profile_settings_path)

      expect(SignupEmailVerification.unverified.where(user_id: user.id).count).to eq(1)
      v2 = SignupEmailVerification.unverified.find_by!(user_id: user.id)
      expect(v2.id).to eq(first_id)
      expect(v2.email).to eq(SignupEmailVerification.normalize_email(second_email))
    end
  end

  describe "GET /profile/email/verify" do
    let(:user) do
      create(:user,
        auth_method: :discord,
        email: "ph_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))
    end

    let(:new_email) { "confirmed_#{SecureRandom.hex(4)}@example.com" }

    it "applies email and verification timestamp" do
      v = SignupEmailVerification.create!(user_id: user.id, email: new_email)
      raw = v.issue!(ip_address: "127.0.0.1")

      get verify_profile_email_path(token: raw)

      expect(response).to redirect_to(profile_settings_path)
      user.reload
      expect(user.email).to eq(new_email)
      expect(user.signup_email_verified_at).to be_present
    end

    it "does not burn the verification token when user email update fails" do
      user = create(:user,
        auth_method: :discord,
        email: "ph_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))

      new_email = "confirmed_#{SecureRandom.hex(4)}@example.com"
      v = SignupEmailVerification.create!(user_id: user.id, email: new_email)
      raw = v.issue!(ip_address: "127.0.0.1")

      attempt_key = :"profile_email_verify_attempt_#{user.id}"
      Thread.current[attempt_key] = 0

      allow_any_instance_of(User).to receive(:update!).and_wrap_original do |method, *args, **kwargs, &block|
        if method.receiver.id == user.id
          Thread.current[attempt_key] += 1 if Thread.current[attempt_key]
          if Thread.current[attempt_key] == 1
            method.receiver.errors.add(:email, "simulated failure")
            raise ActiveRecord::RecordInvalid, method.receiver
          end
        end
        method.call(*args, **kwargs, &block)
      end

      get verify_profile_email_path(token: raw)

      expect(response).to redirect_to(profile_settings_path)
      expect(flash[:alert]).to be_present
      v.reload
      expect(v.verified_at).to be_nil
      expect(v.token_digest).to be_present

      get verify_profile_email_path(token: raw)
      expect(response).to redirect_to(profile_settings_path)

      user.reload
      expect(user.email).to eq(new_email)
      expect(user.signup_email_verified_at).to be_present
    ensure
      Thread.current[attempt_key] = nil if defined?(attempt_key) && attempt_key
    end
  end

  describe "JSON API without verified real email" do
    let!(:free_plan) do
      create(:pricing_plan,
        name: "Free",
        price: 0,
        price_display: "$0",
        period: "forever",
        max_guilds: 1,
        max_members_per_guild: 10,
        active: true,
        display_order: 1)
    end

    let(:api_user) do
      create(:user,
        auth_method: :discord,
        email: "placeholder_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))
    end

    before do
      api_user.generate_otp_secret_if_needed unless api_user.otp_secret.present?
      api_user.update!(mfa_enabled: true, mfa_verified: true)
      create(:subscription, user: api_user, pricing_plan: free_plan) unless api_user.subscriptions.any?
    end

    it "does not block GET /api/v1/users/:id for JSON when real email is unverified" do
      get "/api/v1/users/#{api_user.id}", headers: auth_headers_with_token(api_user), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
