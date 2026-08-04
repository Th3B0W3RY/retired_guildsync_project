# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Settings Auth Method Switching", type: :request do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }

  describe "Switching from Discord to MFA" do
    let(:user) do
      u = create(:user,
                 email: "switcher@example.com",
                 username: "switcher",
                 password: "password123",
                 password_confirmation: "password123",
                 auth_method: "discord",
                 mfa_enabled: true,
                 mfa_verified: true)
      create(:user_discord_connection, user: u)
      create(:subscription, user: u, pricing_plan: free_plan)
      u
    end

    before do
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "switches auth method from Discord to MFA" do
      expect(user.auth_method).to eq("discord")
      
      patch "/auth/discord/toggle_method", params: { auth_method: "mfa" }
      
      expect(response).to redirect_to(account_settings_path)
      expect(flash[:notice]).to include("Authentication method updated to MFA Login")
      
      user.reload
      expect(user.auth_method).to eq("mfa")
    end

    it "prevents switching to MFA if MFA is not enabled" do
      user.update!(mfa_enabled: false, mfa_verified: false)
      
      patch "/auth/discord/toggle_method", params: { auth_method: "mfa" }
      
      expect(response).to redirect_to(mfa_setup_path)
      expect(flash[:alert]).to include("Set up MFA before switching")
      
      user.reload
      expect(user.auth_method).to eq("discord") # Should not change
    end
  end

  describe "Switching from MFA to Discord" do
    let(:user) do
      u = create(:user, :with_mfa,
                 email: "switcher2@example.com",
                 username: "switcher2",
                 password: "password123",
                 password_confirmation: "password123",
                 auth_method: "mfa")
      create(:user_discord_connection, user: u)
      create(:subscription, user: u, pricing_plan: free_plan)
      u
    end

    before do
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "switches auth method from MFA to Discord" do
      expect(user.auth_method).to eq("mfa")
      
      patch "/auth/discord/toggle_method", params: { auth_method: "discord" }
      
      expect(response).to redirect_to(account_settings_path)
      expect(flash[:notice]).to include("Authentication method updated to Discord Login")
      
      user.reload
      expect(user.auth_method).to eq("discord")
    end

    it "prevents switching to Discord if Discord is not connected" do
      # Remove Discord connection
      user.user_discord_connection.destroy
      user.reload
      
      patch "/auth/discord/toggle_method", params: { auth_method: "discord" }
      
      expect(response).to redirect_to(account_settings_path)
      expect(flash[:alert]).to include("Connect Discord first before enabling Discord Login")
      
      user.reload
      expect(user.auth_method).to eq("mfa") # Should not change
    end
  end
end

