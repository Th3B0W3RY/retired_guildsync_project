# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account creation", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe "GET /create_account" do
    it "loads the email verification entry page" do
      get create_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("account_creation.show.title"))
      expect(response.body).to include(I18n.t("account_creation.show.submit"))
    end
  end

  describe "POST /create_account" do
    it "does not send verification email when the address already has a completed account" do
      create(:user, email: "existing@example.com", registration_completed_at: Time.current)

      expect {
        post create_account_path, params: { email: "existing@example.com" }
      }.not_to change(SignupEmailVerification, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("account_creation.email_taken"))
    end

    it "sends a verification email and shows the check inbox step" do
      expect {
        post create_account_path, params: { email: "new@example.com" }
      }.to change(SignupEmailVerification, :count).by(1)

      expect(response).to redirect_to(create_account_sent_path)
      expect(enqueued_jobs.size).to eq(1)
      verification = SignupEmailVerification.last
      expect(verification.email).to eq("new@example.com")
      expect(verification.token_digest).to be_present
    end

    it "rotates the verification token when resending" do
      post create_account_path, params: { email: "rotate@example.com" }
      verification = SignupEmailVerification.last
      original_digest = verification.token_digest
      verification.update!(sent_at: 2.minutes.ago)

      post resend_create_account_verification_path

      expect(response).to redirect_to(create_account_sent_path)
      expect(verification.reload.token_digest).to be_present
      expect(verification.token_digest).not_to eq(original_digest)
      expect(verification.send_count).to eq(2)
    end
  end

  describe "verification and backup code gate" do
    it "creates a provisional user, shows one backup code, and blocks method choice until confirmed" do
      verification = SignupEmailVerification.create!(email: "verified@example.com")
      raw_token = verification.issue!(ip_address: "127.0.0.1")

      get create_account_verify_path(token: raw_token)

      expect(response).to redirect_to(create_account_backup_code_path)
      user = User.find_by!(email: "verified@example.com")
      expect(user).to be_pending_registration
      expect(user.signup_email_verified_at).to be_present
      expect(user.backup_codes.active.count).to eq(1)

      get create_account_choose_method_path
      expect(response).to redirect_to(create_account_backup_code_path)

      post create_account_backup_code_path, params: { backup_code_saved: "1" }
      expect(response).to redirect_to(create_account_choose_method_path)
      expect(user.reload.backup_code_acknowledged_at).to be_present
    end

    it "does not consume verification when provisional user creation fails" do
      verification = SignupEmailVerification.create!(email: "dual@example.com")
      raw = verification.issue!(ip_address: "127.0.0.1")

      attempts = 0
      allow(AccountCreation::ProvisionalUserBuilder).to receive(:call).and_wrap_original do |method, **kwargs|
        attempts += 1
        if attempts == 1
          u = User.new
          u.errors.add(:base, "simulated")
          raise ActiveRecord::RecordInvalid, u
        end
        method.call(**kwargs)
      end

      get create_account_verify_path(token: raw)

      expect(response).to redirect_to(create_account_path)
      expect(flash[:alert]).to eq(I18n.t("account_creation.email_taken"))
      verification.reload
      expect(verification.verified_at).to be_nil
      expect(verification.token_digest).to be_present

      get create_account_verify_path(token: raw)
      expect(response).to redirect_to(create_account_backup_code_path)
    end

    it "does not consume verification when backup code generation fails" do
      verification = SignupEmailVerification.create!(email: "backup-fail@example.com")
      raw = verification.issue!(ip_address: "127.0.0.1")

      attempts = 0
      allow(BackupCodeGenerator).to receive(:generate_for_user).and_wrap_original do |method, user|
        attempts += 1
        raise "simulated backup code failure" if attempts == 1

        method.call(user)
      end
      allow(Rails.logger).to receive(:error).and_call_original
      allow(Rails.logger).to receive(:error).with(/\[AccountCreation\] email verification failed/)

      get create_account_verify_path(token: raw)

      expect(response).to redirect_to(create_account_path)
      expect(flash[:alert]).to eq(I18n.t("account_creation.start_over"))
      verification.reload
      expect(verification.verified_at).to be_nil
      expect(verification.token_digest).to be_present
      expect(User.find_by(email: "backup-fail@example.com")).to be_nil

      get create_account_verify_path(token: raw)

      expect(response).to redirect_to(create_account_backup_code_path)
      user = User.find_by!(email: "backup-fail@example.com")
      expect(user.backup_codes.active.count).to eq(1)
      expect(verification.reload.verified_at).to be_present
    end

    it "rejects a verification link after successful use" do
      verification = SignupEmailVerification.create!(email: "reuse@example.com")
      raw = verification.issue!(ip_address: "127.0.0.1")

      get create_account_verify_path(token: raw)
      expect(response).to redirect_to(create_account_backup_code_path)

      get create_account_verify_path(token: raw)

      expect(response).to redirect_to(create_account_path)
      expect(flash[:alert]).to eq(I18n.t("account_creation.invalid_or_expired"))
    end

    it "rejects stale verification links after a resend rotates the token" do
      verification = SignupEmailVerification.create!(email: "stale@example.com")
      old_token = verification.issue!(ip_address: "127.0.0.1")
      verification.update!(sent_at: 2.minutes.ago)
      verification.issue!(ip_address: "127.0.0.1")

      get create_account_verify_path(token: old_token)

      expect(response).to redirect_to(create_account_path)
      expect(User.find_by(email: "stale@example.com")).to be_nil
    end

    it "rejects profile email verification tokens on the signup verify route" do
      u = create(:user,
        email: "disco_#{SecureRandom.hex(4)}@discord.guildsync.local",
        signup_email_verified_at: nil,
        discord_user_id: SecureRandom.hex(8))
      v = SignupEmailVerification.create!(user_id: u.id, email: "prof_#{SecureRandom.hex(4)}@example.com")
      raw = v.issue!(ip_address: "127.0.0.1")

      get create_account_verify_path(token: raw)

      expect(response).to redirect_to(create_account_path)
      expect(v.reload.verified_at).to be_nil
    end
  end
end
