# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Authentication Persistence Across Pages", type: :request do
  let(:pricing_plan) { create(:pricing_plan, name: "Upgraded", price: 19.99, max_guilds: 10, active: true) }
  
  describe "MFA Auth Method User" do
    let(:user) do
      u = create(:user, :with_mfa, password: "password123", password_confirmation: "password123", auth_method: "mfa", skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: pricing_plan, status: :active)
      u
    end

    before do
      # Sign in and complete MFA verification
      post "/sign_in", params: {
        user: {
          email: user.email,
          password: "password123"
        }
      }
      
      # Complete MFA verification
      post "/mfa/verify", params: {
        code: ROTP::TOTP.new(user.otp_secret).now
      }
      
      # Verify session is set
      expect(session[:mfa_verified]).to be true
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing dashboard" do
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing member dashboard" do
      get member_dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing guild applications" do
      get guild_applications_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing new guild application" do
      get new_guild_application_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing new guild" do
      get new_guild_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing my guilds" do
      get my_guilds_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing leaderboard" do
      get leaderboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing contact support" do
      get contact_support_path
      # Contact support redirects to external support center; auth is maintained until redirect
      expect(response).to be_redirect
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    context "when user owns a guild" do
      let!(:guild) { create(:guild, owner: user) }

      it "maintains authentication when accessing guild dashboard" do
        get guild_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing guild settings" do
        get guild_settings_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing guild members" do
        get guild_members_list_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing review applications" do
        get guild_review_applications_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing invite members" do
        get guild_invite_members_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing schedule events" do
        get guild_schedule_events_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing members gear" do
        get guild_members_gear_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing guild activity feed" do
        get guild_activity_feed_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing Discord connection" do
        get guild_discord_connection_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end
    end

    it "maintains authentication when navigating between multiple pages" do
      # Navigate through a sequence of pages
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      
      get member_dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
      
      get guild_applications_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
      
      get leaderboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "signs out user and prevents access to protected pages" do
      # Verify user is authenticated
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      
      # Sign out
      delete "/sign_out"
      # Sign out redirects
      expect(response).to be_redirect
      
      # Verify user is no longer authenticated - accessing protected pages should redirect
      get dashboard_path
      expect(response).to be_redirect
      # User should not be able to access protected pages after sign out
      # The redirect indicates authentication is required
      expect(response.status).to eq(302)
    end
  end

  describe "Discord Auth Method User" do
    let(:user) do
      u = create(:user, auth_method: "discord", email: "discord_user@example.com")
      create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
      u
    end

    before do
      # Sign in Discord user (they don't need MFA)
      sign_in user
      # Set session flags for Discord users by making a request
      get dashboard_path
      # Verify session is set
      expect(session[:mfa_verified]).to be true
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing dashboard" do
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing member dashboard" do
      get member_dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing guild applications" do
      get guild_applications_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication when accessing leaderboard" do
      get leaderboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    context "when user owns a guild" do
      let!(:guild) { create(:guild, owner: user) }

      it "maintains authentication when accessing guild dashboard" do
        get guild_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing guild settings" do
        get guild_settings_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end

      it "maintains authentication when accessing Discord connection" do
        get guild_discord_connection_path(guild)
        expect(response).to have_http_status(:success)
        expect(controller.current_user).to eq(user)
        expect(session[:user_id]).to eq(user.id)
      end
    end

    it "maintains authentication when navigating between multiple pages" do
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      
      get member_dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
      
      get guild_applications_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "signs out user and prevents access to protected pages" do
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      
      delete "/sign_out"
      # Sign out redirects
      expect(response).to be_redirect
      
      get dashboard_path
      expect(response).to be_redirect
      # User should not be able to access protected pages after sign out
      # The redirect indicates authentication is required
      expect(response.status).to eq(302)
    end
  end

  describe "Session persistence after actions" do
    let(:user) do
      u = create(:user, :with_mfa, password: "password123", password_confirmation: "password123", auth_method: "mfa", skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: pricing_plan)
      u
    end
    let!(:guild) { create(:guild, owner: user) }

    before do
      post "/sign_in", params: {
        user: {
          email: user.email,
          password: "password123"
        }
      }
      
      post "/mfa/verify", params: {
        code: ROTP::TOTP.new(user.otp_secret).now
      }
    end

    it "maintains authentication after creating a guild application" do
      other_guild = create(:guild)
      
      post guild_applications_path, params: {
        guild_id: other_guild.id,
        discord_username: "testuser",
        message: "I want to join"
      }
      
      expect(response).to redirect_to(guild_applications_path)
      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication after creating a guild" do
      # Create a test game for guild creation
      test_game = Game.find_or_create_by!(name: "Test Game", slug: "test-game") do |g|
        g.description = "Default test game"
        g.active = true
        g.ocr_config = {}
      end
      
      post guilds_path, params: {
        guild: {
          name: "New Guild",
          description: "A new guild",
          game_ids: [test_game.id],
          primary_game_id: test_game.id
        }
      }
      
      expect(response).to be_redirect
      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end

    it "maintains authentication after viewing guild settings" do
      get guild_settings_path(guild)
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
      
      # Navigate to another page
      get dashboard_path
      expect(response).to have_http_status(:success)
      expect(controller.current_user).to eq(user)
      expect(session[:user_id]).to eq(user.id)
    end
  end
end

