# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MFA Flow", type: :request do
  let(:user) { create(:user) }
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }

  describe "GET /mfa/setup" do
    context "when user is not signed in" do
      it "redirects to login" do
        get "/mfa/setup"
        # May redirect to root or login depending on configuration
        expect(response).to be_redirect
        expect(response.location).to match(/\/(login|$)/)
      end
    end

    context "when user is signed in" do
      before { sign_in user }

      context "with incomplete profile" do
        let(:user) do
          password = SecureRandom.hex(32)
          user = User.new(
            email: "testuser_#{SecureRandom.hex}@discord.guildsync.local",
            username: "testuser",
            password: password,
            password_confirmation: password,
            confirmed_at: Time.current
          )
          user.save(validate: false)
          user
        end

        it "redirects to profile completion" do
          get "/mfa/setup"
          
          expect(response).to redirect_to(complete_profile_path)
          expect(flash[:alert]).to include("complete your profile")
        end
      end

      context "with Discord auth (helper treats session as verified)" do
        let(:user) { create(:user, :discord_auth) }

        it "does not render the member app sidebar on MFA setup (isolated shell)" do
          get "/mfa/setup"
          expect(response).to have_http_status(:success)
          expect(response.body).not_to include('id="sidebar"')
        end
      end

      context "with complete profile" do
        it "shows MFA setup page with QR code" do
          set_mfa_verified_in_session
          get "/mfa/setup"
          
          expect(response).to have_http_status(:success)
          expect(response.body).to include("Enable Multi-Factor Authentication")
          expect(response.body).to include("QR")
        end

        it "generates OTP secret if not present" do
          set_mfa_verified_in_session
          # User may already have OTP secret from factory, so clear it
          user.update!(otp_secret: nil)
          expect(user.reload.otp_secret).to be_nil

          get "/mfa/setup"

          user.reload
          expect(user.otp_secret).to be_present
        end

        it "renders without error when OTP secret cannot be persisted" do
          set_mfa_verified_in_session
          user.update!(otp_secret: nil)

          allow_any_instance_of(User).to receive(:update!).and_wrap_original do |method, *args|
            attrs = args.first
            if method.receiver.id == user.id && attrs.is_a?(Hash) && attrs.key?(:otp_secret)
              raise StandardError, "simulated persistence failure"
            end
            method.call(*args)
          end

          get "/mfa/setup"

          expect(response).to have_http_status(:success)
          expect(response.body).to include(I18n.t("mfa_setup.show.setup_unavailable"))
          expect(response.body).not_to include(I18n.t("mfa_setup.show.verify_button"))
        end
      end
    end
  end

  describe "POST /mfa/verify_setup" do
    before do
      sign_in user
      user.generate_otp_secret_if_needed
    end

    context "with valid verification code" do
      it "enables MFA and redirects to dashboard" do
        totp = ROTP::TOTP.new(user.otp_secret)
        code = totp.now
        
        post "/mfa/verify_setup", params: { code: code }
        
        expect(response).to redirect_to(dashboard_path)
        user.reload
        expect(user.mfa_enabled).to be true
        expect(user.mfa_verified).to be true
      end
    end

    context "with invalid verification code" do
      it "shows error and does not enable MFA" do
        post "/mfa/verify_setup", params: { code: "000000" }
        
        expect(response).to have_http_status(:unprocessable_content)
        user.reload
        expect(user.mfa_enabled).to be false
      end
    end
  end

  describe "GET /dashboard before session MFA" do
    let(:mfa_user) { create(:user, :with_mfa) }

    before { sign_in mfa_user }

    it "redirects to MFA verification instead of rendering the dashboard" do
      get dashboard_path
      expect(response).to redirect_to(mfa_verification_path(return_to: dashboard_path))
    end

    it "redirects recent_activity poll to MFA verification (before controller runs)" do
      get dashboard_recent_activity_path
      expect(response).to redirect_to(mfa_verification_path(return_to: dashboard_recent_activity_path))
    end
  end

  describe "POST /mfa/verify" do
    let(:mfa_user) { create(:user, :with_mfa) }

    before do
      post "/sign_in", params: {
        user: {
          email: mfa_user.email,
          password: "password123"
        }
      }
    end

    context "with valid code" do
      it "verifies MFA and completes login" do
        totp = ROTP::TOTP.new(mfa_user.otp_secret)
        code = totp.now
        
        post "/mfa/verify", params: { code: code }
        
        expect(response).to redirect_to(dashboard_path)
        expect(session[:mfa_verified]).to be true
      end
    end

    context "with invalid code" do
      it "rejects invalid code" do
        post "/mfa/verify", params: { code: "000000" }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(session[:mfa_verified]).to be_nil
      end
    end
  end
end

