# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Discord OAuth Complete Flow", type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:client_id) { "test_client_id_123" }
  let(:client_secret) { "test_client_secret_456" }
  let(:redirect_uri) { "http://localhost:5000/auth/discord/callback" }
  let(:oauth_state) { SecureRandom.hex(32) }
  let(:oauth_code) { "test_oauth_code_789" }

  let(:fake_token_response) do
    {
      "access_token" => "fake_access_token_12345",
      "refresh_token" => "fake_refresh_token_67890",
      "expires_in" => 604800,
      "token_type" => "Bearer",
      "scope" => "identify guilds"
    }
  end

  let(:fake_user_info) do
    {
      "id" => "987654321098765432",
      "username" => "DiscordUser",
      "discriminator" => "1234",
      "avatar" => "test_avatar_hash"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_SECRET").and_return(client_secret)
    allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(nil)

    allow_any_instance_of(DiscordUserOAuthService).to receive(:client_id).and_return(client_id)
    allow_any_instance_of(DiscordUserOAuthService).to receive(:client_secret).and_return(client_secret)
    allow_any_instance_of(DiscordUserOAuthService).to receive(:exchange_code_for_token).and_return(fake_token_response)
    allow_any_instance_of(DiscordUserOAuthService).to receive(:get_user_info).and_return(fake_user_info)
    allow_any_instance_of(DiscordUserOAuthService).to receive(:avatar_url).and_return("https://cdn.discordapp.com/avatars/987654321098765432/test_avatar_hash.png")
  end

  describe "Complete Discord Signup Flow" do
    it "completes full gated Discord signup with a verified email" do
      verification = SignupEmailVerification.create!(email: "discorduser@example.com")
      token = verification.issue!(ip_address: "127.0.0.1")
      get create_account_verify_path(token: token)
      expect(response).to redirect_to(create_account_backup_code_path)

      post create_account_backup_code_path, params: { backup_code_saved: "1" }
      expect(response).to redirect_to(create_account_choose_method_path)

      post create_account_discord_path
      expect(response).to redirect_to(discord_login_path(signup: true))

      # Step 1: User continues into gated Discord signup
      get "/auth/discord", params: { signup: true }

      # Should redirect to Discord OAuth
      expect(response).to have_http_status(:redirect)
      expect(response.headers["Location"]).to include("discord.com/api/oauth2/authorize")
      expect(session[:discord_oauth_from]).to eq("signup")

      # Step 2: Simulate Discord callback with OAuth code
      # Use the actual state set by the controller rather than a hardcoded one
      state = session[:discord_oauth_state]
      get "/auth/discord/callback", params: { code: oauth_code, state: state }

      # Callback redirects to verify session, which then sends to profile completion or dashboard
      expect(response).to be_redirect
      expect(response.location).to include("/auth/discord/verify")

      # Step 3: Find the created user
      user = User.find_by(discord_user_id: fake_user_info["id"])
      expect(user).to be_present
      expect(user.email).to eq("discorduser@example.com")
      expect(user.registration_completed_at).to be_present
      expect(user.user_discord_connection).to be_present
    end

    it "completes Discord login for existing user" do
      # Create existing user with Discord connection
      existing_user = create(:user, discord_user_id: fake_user_info["id"])
      create(:user_discord_connection,
             user: existing_user,
             discord_user_id: fake_user_info["id"],
             access_token: "old_token",
             refresh_token: "old_refresh")

      # Step 1: User clicks Discord login
      get "/auth/discord"

      expect(response).to have_http_status(:redirect)
      expect(session[:discord_oauth_from]).to eq("login")

      # Step 2: Simulate Discord callback
      # Use the actual state set by the controller rather than a hardcoded one
      state = session[:discord_oauth_state]
      get "/auth/discord/callback", params: { code: oauth_code, state: state }

      # Callback redirects to verify session, which then sends to dashboard
      expect(response).to be_redirect
      expect(response.location).to match(%r{/auth/discord/verify|/dashboard})

      # Verify user is signed in using Devise/Warden session data
      expect(user_signed_in_via_session?).to be true
    end

    it "handles Discord OAuth errors gracefully" do
      get "/auth/discord"
      # Use the actual state set by the controller
      state = session[:discord_oauth_state]

      get "/auth/discord/callback", params: { error: "access_denied", error_description: "User denied", state: state }

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to include("Discord login failed")
    end
  end

  describe "Discord Account Linking" do
    let(:user) { create(:user) }

    before do
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "links Discord account to existing user" do
      get "/auth/discord" # Set up session and state
      session[:discord_oauth_link_only] = true
      # Use the actual state set by the controller
      state = session[:discord_oauth_state]

      get "/auth/discord/callback", params: { code: oauth_code, state: state }

      expect(response).to redirect_to(account_settings_path)
      expect(flash[:notice]).to include("Discord account linked successfully")

      user.reload
      expect(user.user_discord_connection).to be_present
      expect(user.user_discord_connection.discord_user_id).to eq(fake_user_info["id"])
    end
  end

  private

  # Helper to check if a Devise user is signed in by inspecting the Warden session
  # This mimics Devise's `user_signed_in?` helper in the request-spec context.
  def user_signed_in_via_session?
    warden_data = session["warden.user.user.key"]
    warden_data.present?
  end
end
