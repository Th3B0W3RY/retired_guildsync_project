# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile Completion", type: :request do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }

  describe "GET /profile/complete" do
    context "when user has incomplete profile" do
      let(:discord_user) do
        user = User.new(
          email: "testuser_#{SecureRandom.hex}@discord.guildsync.local",
          username: "testuser123",
          password: SecureRandom.hex(32),
          auth_method: "discord",
          mfa_enabled: false,
          mfa_verified: false,
          confirmed_at: Time.current
        )
        user.save(validate: false)
        user
      end

      before { sign_in discord_user }

      it "shows profile completion form" do
        get complete_profile_path
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Complete Your Profile")
      end
    end

    context "when user has complete profile" do
      let(:user) { create(:user) }

      before { sign_in user }

      it "redirects to account settings" do
        get complete_profile_path
        
        expect(response).to redirect_to(account_settings_path)
      end
    end
  end

  describe "PATCH /profile/complete" do
    let(:discord_user) do
      user = User.new(
        email: "testuser_#{SecureRandom.hex}@discord.guildsync.local",
        username: "testuser123",
        password: SecureRandom.hex(32),
        auth_method: "discord",
        mfa_enabled: false,
        mfa_verified: false,
        confirmed_at: Time.current
      )
      user.save(validate: false)
      user
    end

    before { sign_in discord_user }

    it "completes profile and redirects to MFA setup" do
      patch complete_profile_path, params: {
        user: {
          email: "testuser@example.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        }
      }
      
      expect(response).to redirect_to(mfa_setup_path)
      expect(flash[:notice]).to eq(I18n.t("profile_completion.update.success"))
      
      discord_user.reload
      expect(discord_user.email).to eq("testuser@example.com")
      expect(discord_user.username).to eq("testuser")
      expect(discord_user.encrypted_password).to be_present
    end

    it "validates required fields" do
      patch complete_profile_path, params: {
        user: {
          email: "",
          username: "",
          password: ""
        }
      }
      
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to be_present
    end
  end
end

