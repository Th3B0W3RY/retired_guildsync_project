# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise confirmations", type: :request do
  include ActiveJob::TestHelper
  describe "GET /users/confirmation/new" do
    it "renders resend confirmation form" do
      get new_user_confirmation_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("confirmations.new.title"))
    end
  end

  describe "GET /users/confirmation" do
    it "confirms the user and redirects to MFA setup" do
      user = create(:user, :unconfirmed,
                    email: "confirm_flow@example.com",
                    username: "confirmflow",
                    password: "password123",
                    password_confirmation: "password123")
      raw, enc = Devise.token_generator.generate(User, :confirmation_token)
      user.update_columns(confirmation_token: enc, confirmation_sent_at: Time.current)

      get user_confirmation_path, params: { confirmation_token: raw }

      expect(response).to redirect_to(mfa_setup_path)
      expect(user.reload.confirmed_at).to be_present
    end
  end

  describe "POST /users/confirmation" do
    before { ActionMailer::Base.deliveries.clear }

    it "redirects to login with notice when resend succeeds (no new_user_session_path)" do
      user = create(:user, :unconfirmed,
                    email: "resend-confirm@example.com",
                    username: "resendconfirm",
                    password: "password123",
                    password_confirmation: "password123")

      post user_confirmation_path, params: { user: { email: user.email } }

      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to eq(I18n.t("devise.confirmations.send_paranoid_instructions"))
      perform_enqueued_jobs
      expect(ActionMailer::Base.deliveries).not_to be_empty
    end

    it "redirects to login for unknown email (paranoid, no enumeration)" do
      post user_confirmation_path, params: { user: { email: "nobody-#{SecureRandom.hex(4)}@example.com" } }

      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to eq(I18n.t("devise.confirmations.send_paranoid_instructions"))
      perform_enqueued_jobs
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "shows an error when the email is already confirmed (no new email sent)" do
      user = create(:user,
                    email: "already-confirmed@example.com",
                    username: "alreadyconfirmed",
                    password: "password123",
                    password_confirmation: "password123")

      expect(user.confirmed?).to be true

      post user_confirmation_path, params: { user: { email: user.email } }

      expect(response).to redirect_to(new_user_confirmation_path)
      expect(flash[:alert]).to eq(I18n.t("confirmations.create.already_registered"))
      perform_enqueued_jobs
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
