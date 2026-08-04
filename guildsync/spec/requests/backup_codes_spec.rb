# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Backup codes", type: :request do
  describe "GET /password/new (Account Recovery page)" do
    it "shows account recovery with email reset and backup code options" do
      # Regression: Devise passwords use application layout + active_compliance_warning_banner (ApplicationHelper).
      get new_password_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("passwords.account_recovery.title"))
      expect(response.body).to include("email-reset-form")
      expect(response.body).to include("backup-code-form")
      expect(response.body).to include(I18n.t("passwords.account_recovery.verify_backup_code"))
      expect(response.body).to include(I18n.t("passwords.account_recovery.backup_code_label"))
      expect(response.body).to include("backup_code")
      expect(response.body).to include(I18n.t("passwords.account_recovery.email_send_button"))
    end

    it "includes back to sign in link" do
      get new_password_path
      expect(response.body).to include("Back to Sign In")
      expect(response.body).to include(login_path)
    end
  end

  describe "POST /backup_codes/generate" do
    it "requires authentication" do
      post generate_backup_codes_path
      expect(response).to have_http_status(:redirect)
      redirect_path = URI.parse(response.redirect_url).path
      expect([ login_path, root_path ]).to include(redirect_path)
    end

    context "when signed in" do
      let(:user) { create(:user, :with_mfa) }

      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
        allow_any_instance_of(BackupCodesController).to receive(:require_mfa_if_enabled)
        allow_any_instance_of(BackupCodesController).to receive(:ensure_fully_authenticated)
      end

      it "emails a regenerated backup code and creates one active record" do
        user.update!(signup_email_verified_at: Time.current, backup_code_regenerated_at: 4.months.ago)

        post generate_backup_codes_path
        expect(response).to redirect_to(account_settings_path)
        expect(BackupCode.count).to eq(1)
        expect(BackupCode.active.count).to eq(1)
      end

      it "records generation timestamp on the user" do
        user.update!(signup_email_verified_at: Time.current, backup_code_regenerated_at: 4.months.ago)

        expect { post generate_backup_codes_path }.to change { user.reload.last_backup_generation_at }.from(nil)
        expect(user.last_backup_generation_at).to be_within(2.seconds).of(Time.current)
      end

      it "blocks regeneration during the 3 month cooldown" do
        user.update!(signup_email_verified_at: Time.current, backup_code_regenerated_at: 1.month.ago)

        expect { post regenerate_backup_codes_path }.not_to change(BackupCode, :count)
        expect(response).to redirect_to(account_settings_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /backup_codes/verify" do
    let(:user) { create(:user) }
    let(:result) { BackupCodeGenerator.generate_for_user(user) }
    let(:code) { result[:codes].first.gsub("-", "") }

    it "redirects to recover with valid email and code" do
      post verify_backup_codes_path, params: { email: user.email, backup_code: code }
      expect(response).to redirect_to(recover_account_path)
      expect(session[:recovery_user_id]).to eq(user.id)
      expect(session[:recovery_method]).to eq("backup_code")
    end

    it "redirects to new_password with invalid code" do
      post verify_backup_codes_path, params: { email: user.email, backup_code: "INVALID1234567890123456" }
      expect(response).to redirect_to(new_password_path)
      expect(flash[:alert]).to be_present
      expect(session[:recovery_user_id]).to be_nil
    end

    it "redirects to new_password with unknown email" do
      post verify_backup_codes_path, params: { email: "nobody@example.com", backup_code: code }
      expect(response).to redirect_to(new_password_path)
      expect(flash[:alert]).to be_present
    end

    it "returns the same alert message for unknown email and invalid code" do
      post verify_backup_codes_path, params: { email: user.email, backup_code: "INVALID1234567890123456" }
      invalid_code_message = flash[:alert]

      post verify_backup_codes_path, params: { email: "nobody@example.com", backup_code: code }
      unknown_email_message = flash[:alert]

      expect(unknown_email_message).to eq(invalid_code_message)
    end
  end

  describe "GET /account/recover" do
    it "redirects to new_password when no recovery session" do
      get recover_account_path
      expect(response).to redirect_to(new_password_path)
      expect(flash[:alert]).to be_present
    end

    context "with recovery session" do
      let(:user) { create(:user) }

      it "shows recovery form after verifying backup code" do
        result = BackupCodeGenerator.generate_for_user(user)
        post verify_backup_codes_path, params: { email: user.email, backup_code: result[:codes].first.gsub("-", "") }
        expect(response).to redirect_to(recover_account_path)
        # Session is set by verify; request recover page in same example (session persists)
        get recover_account_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Reset Your Account")
        expect(response.body).to include("Set New Password")
        expect(response.body).to include("Recovering with Backup Code")
        expect(response.body).to include("/account/recover")
      end
    end
  end
end
