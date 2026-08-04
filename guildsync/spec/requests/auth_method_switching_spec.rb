# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth Method Switching", type: :request do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }

  describe "PATCH /auth/discord/toggle_method" do
    context "switching from Discord to MFA" do
      let(:user) do
        u = create(:user,
                   email: "testuser@example.com",
                   username: "testuser",
                   password: "password123",
                   password_confirmation: "password123",
                   auth_method: "discord",
                   mfa_enabled: true,
                   mfa_verified: true)
        create(:user_discord_connection, user: u)
        u
      end

      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "switches auth method to MFA" do
        patch "/auth/discord/toggle_method", params: { auth_method: "mfa" }
        
        expect(response).to redirect_to(account_settings_path)
        expect(flash[:notice]).to include("Authentication method updated to MFA Login")
        
        user.reload
        expect(user.auth_method).to eq("mfa")
      end
    end

    context "switching from MFA to Discord" do
      let(:user) do
        u = create(:user, :with_mfa,
                   email: "testuser@example.com",
                   username: "testuser",
                   password: "password123",
                   password_confirmation: "password123",
                   auth_method: "mfa")
        create(:user_discord_connection, user: u)
        u
      end

      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "switches auth method to Discord" do
        patch "/auth/discord/toggle_method", params: { auth_method: "discord" }
        
        expect(response).to redirect_to(account_settings_path)
        expect(flash[:notice]).to include("Authentication method updated to Discord Login")
        
        user.reload
        expect(user.auth_method).to eq("discord")
      end
    end

    context "preventing invalid switches" do
      let(:user) do
        u = create(:user,
                   email: "testuser@example.com",
                   username: "testuser",
                   password: "password123",
                   password_confirmation: "password123",
                   auth_method: "discord",
                   mfa_enabled: false)
        create(:user_discord_connection, user: u)
        u
      end

      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "prevents switching to MFA without MFA enabled" do
        patch "/auth/discord/toggle_method", params: { auth_method: "mfa" }
        
        expect(response).to redirect_to(mfa_setup_path)
        expect(flash[:alert]).to include("Set up MFA before switching")
        
        user.reload
        expect(user.auth_method).to eq("discord")
      end
    end

    context "preventing switch to Discord without connection" do
      let(:user) do
        create(:user, :with_mfa,
               email: "testuser@example.com",
               username: "testuser",
               password: "password123",
               password_confirmation: "password123",
               auth_method: "mfa")
      end

      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "prevents switching to Discord without Discord connection" do
        patch "/auth/discord/toggle_method", params: { auth_method: "discord" }
        
        expect(response).to redirect_to(account_settings_path)
        expect(flash[:alert]).to include("Connect Discord first before enabling Discord Login")
        
        user.reload
        expect(user.auth_method).to eq("mfa")
      end
    end
  end
end

