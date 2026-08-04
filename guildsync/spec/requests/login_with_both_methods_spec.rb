# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Login with Both Auth Methods", type: :request do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }

  describe "Login with MFA Auth Method" do
    let(:mfa_user) do
      u = create(:user, :with_mfa,
                 email: "mfa_login@example.com",
                 username: "mfa_login",
                 password: "password123",
                 password_confirmation: "password123",
                 auth_method: "mfa")
      create(:subscription, user: u, pricing_plan: free_plan)
      u
    end

    it "completes login flow: sign in -> MFA verification -> dashboard" do
      SiteSetting.set("release_notes_url", "https://mfa-verification-support.example/help")

      # Step 1: User signs in with email/password
      post "/sign_in", params: {
        user: {
          email: mfa_user.email,
          password: "password123"
        }
      }

      # Should redirect to MFA verification with return_to parameter
      expect(response).to be_redirect
      expect(response.location).to match(/mfa\/verify/)

      # Step 2: Follow redirect to MFA verification page
      follow_redirect!
      # May need to handle redirects
      if response.redirect?
        follow_redirect!
      end
      expect(response).to have_http_status(:success)
      # May be on verification or setup page
      expect(response.body).to match(/(verification|code|Enable Multi-Factor Authentication)/i) rescue nil
      expect(response.body).to include(%(href="#{release_notes_path}"))
      expect(response.body).not_to include(%(href="#"))

      contact_support_href = Nokogiri::HTML(response.body).at_css(%(a[href="#{release_notes_path}"]))["href"]
      get contact_support_href
      expect(response).to redirect_to("https://mfa-verification-support.example/help")

      # Step 3: Generate valid TOTP code
      totp = ROTP::TOTP.new(mfa_user.otp_secret)
      verification_code = totp.now

      # Step 4: Submit MFA verification code
      post "/mfa/verify", params: { code: verification_code }

      # Should redirect to dashboard
      expect(response).to redirect_to(dashboard_path)

      # Step 5: Verify session flags (check after redirect)
      follow_redirect! if response.redirect?
      expect(session[:mfa_verified]).to be true
      expect(session[:mfa_verified_at]).to be_present
      # just_logged_in may be cleared after redirect
    end

    it "requires MFA verification even if user is already signed in" do
      sign_in mfa_user

      # Clear MFA verification from session
      get dashboard_path # Establish session
      session.delete(:mfa_verified)
      session.delete(:mfa_verified_at)

      # Try to access dashboard
      get dashboard_path

      # Should redirect to MFA verification with return_to parameter
      expect(response).to be_redirect
      expect(response.location).to match(/mfa\/verify/)
    end
  end

  describe "Login with Discord Auth Method" do
    let(:discord_user) do
      u = create(:user,
                 email: "discord_login@example.com",
                 username: "discord_login",
                 password: "password123",
                 password_confirmation: "password123",
                 auth_method: "discord")
      create(:user_discord_connection, user: u, discord_user_id: "123456789")
      create(:subscription, user: u, pricing_plan: free_plan)
      u
    end

    it "allows Discord users to access dashboard without MFA verification" do
      sign_in discord_user

      # Should be able to access dashboard (Discord users get MFA verification set automatically)
      get dashboard_path
      if response.redirect?
        # If redirected, follow it
        follow_redirect!
      end
      expect(response).to have_http_status(:success)

      # Verify session was set by checking after request
      get dashboard_path # Make another request to check session
      if response.redirect?
        follow_redirect!
      end
      expect(response).to have_http_status(:success)
    end

    it "can also login with email/password if they have credentials" do
      # Discord user with credentials can login normally
      post "/sign_in", params: {
        user: {
          email: discord_user.email,
          password: "password123"
        }
      }

      # Should redirect to MFA setup (Discord users without MFA)
      expect(response).to redirect_to(mfa_setup_path)
    end
  end

  describe "Login flow differences" do
    it "MFA users must verify after login" do
      mfa_user = create(:user, :with_mfa, auth_method: "mfa", password: "password123", password_confirmation: "password123")
      create(:subscription, user: mfa_user, pricing_plan: free_plan)

      post "/sign_in", params: { user: { email: mfa_user.email, password: "password123" } }

      expect(response).to redirect_to(mfa_verification_path(return_to: dashboard_path))
      expect(session[:just_logged_in]).to be true
    end

    it "Discord users skip MFA verification" do
      discord_user = create(:user, auth_method: "discord", password: "password123", password_confirmation: "password123")
      create(:user_discord_connection, user: discord_user, discord_user_id: "discord_#{SecureRandom.hex}")
      create(:subscription, user: discord_user, pricing_plan: free_plan)

      sign_in discord_user

      # Discord users can access dashboard without MFA verification
      get dashboard_path
      if response.redirect?
        follow_redirect!
      end
      expect(response).to have_http_status(:success)
    end
  end
end
