# frozen_string_literal: true

require "rails_helper"

# Covers the Discord auth persistence bug fixes (v1 + v2):
#
# Bug A   – prompt: "consent" forced the Discord consent screen on every sign-in.
# Bug B1  – mfa_verified_for_session? returned false after 30 min for Discord users.
# Bug B2  – redirect_if_authenticated called reset_session when B1 returned false.
# Bug B3  – require_mfa_if_enabled only set mfa_verified_at once (never refreshed).
# Bug B4  – silent login was blocked by referer heuristic; now uses discord_signed_out cookie.
# Bug C   – (v2) No auto-redirect on login page; users had to manually click Sign In.
# Bug D   – (v2) discord_signed_out not cleared after successful re-auth.
# Bug E   – (v2) silent login always sent users to dashboard, ignoring Devise return_to.
# Bug F   – (v2) discord_uid / discord_seen_before lacked explicit same_site: :lax.
#
# Route helpers:
#   discord_login_path → GET  /auth/discord   (discord_user_auth#start)
#   sign_out_path      → DELETE /sign_out     (sessions#destroy)
#   login_path         → GET  /login          (sessions#new)
#   dashboard_path     → GET  /dashboard
#
# Cookie notes:
#   RSpec request specs use Rack::Test under the hood.  `cookies` returns a
#   Rack::Test::CookieJar that does NOT support .signed for writing.
#   Use `generate_signed_cookie` to produce a value the server's signed jar verifies.
RSpec.describe "Discord Auth Persistence", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:pricing_plan) { create(:pricing_plan, max_guilds: 5) }
  let(:discord_user) do
    user = create(:user, auth_method: "discord", discord_user_id: "111222333")
    create(:subscription, user: user, pricing_plan: pricing_plan)
    user
  end

  # Signs in the Discord user and makes the first HTTP request so that
  # subsequent session[] reads inside examples work correctly.
  def login_discord_user!
    sign_in discord_user
    get dashboard_path
  end

  # Generates a Rails-signed cookie value matching what
  # ActionDispatch::Cookies::SignedKeyRotatingCookieJar produces.
  # Injecting this into the Rack::Test cookie jar lets the server's
  # `cookies.signed[:name]` call verify and read the value.
  def generate_signed_cookie(name, value)
    secret = Rails.application.key_generator.generate_key(
      Rails.application.config.action_dispatch.signed_cookie_salt
    )
    verifier = ActiveSupport::MessageVerifier.new(
      secret,
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    verifier.generate(value.to_json, purpose: "cookie.#{name}")
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug B1 + B3 — Discord users can always access protected pages (no 30-min cap)
  # ──────────────────────────────────────────────────────────────────────────
  describe "Protected page access for Discord users" do
    before { login_discord_user! }

    it "can access the dashboard after sign-in" do
      get dashboard_path
      expect(response).to have_http_status(:success)
    end

    it "is never redirected to MFA verification" do
      get dashboard_path
      expect(response.location.to_s).not_to include("mfa")
    end

    it "can access the dashboard on multiple consecutive requests" do
      3.times do
        get dashboard_path
        expect(response).to have_http_status(:success)
      end
    end

    it "mfa_verified_at is refreshed on every request (timestamp never goes stale)" do
      first_ts = session[:mfa_verified_at]
      expect(first_ts).to be_present

      travel(2.seconds) do
        get dashboard_path
        expect(session[:mfa_verified_at]).to be > first_ts
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug B2 — redirect_if_authenticated must not reset Discord user sessions
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /login when Discord user is already signed in" do
    before { login_discord_user! }

    it "redirects to dashboard" do
      get login_path
      expect(response).to redirect_to(dashboard_path)
    end

    it "user remains authenticated after visiting /login (session not wiped)" do
      get login_path
      follow_redirect!
      expect(response).to have_http_status(:success)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug C (v2) — login page auto sign-in for returning Discord users
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /login auto sign-in for returning Discord users" do
    context "when discord_uid cookie is present and discord_signed_out is absent" do
      before do
        create(:user_discord_connection, user: discord_user, discord_user_id: "111222333",
               refresh_token: "valid_refresh_token", expires_at: 1.hour.from_now)
        get login_path
        cookies[:discord_uid] = generate_signed_cookie(:discord_uid, "111222333")
      end

      it "signs the user in inline and redirects straight to the dashboard (one hop, no /auth/discord)" do
        get login_path
        expect(response).to redirect_to(dashboard_path)
      end
    end

    context "when discord_uid is present but discord_signed_out is also present (explicit sign-out)" do
      before do
        login_discord_user!
        delete sign_out_path
        # Rack::Test carries the discord_signed_out cookie forward automatically.
        expect(response.cookies["discord_signed_out"]).to be_present
      end

      it "shows the login page normally (does NOT auto-redirect to Discord)" do
        get login_path
        expect(response).to have_http_status(:success)
        expect(response).not_to redirect_to(discord_login_path)
      end
    end

    context "when force_load param is present (post-sign-out forced reload)" do
      before do
        get login_path
        cookies[:discord_uid] = generate_signed_cookie(:discord_uid, "111222333")
      end

      it "shows the login page normally (does NOT auto-redirect)" do
        get login_path(force_load: 1)
        expect(response).not_to redirect_to(discord_login_path)
      end
    end

    context "when no discord_uid cookie is present (first-time or disconnected user)" do
      it "shows the login page normally" do
        get login_path
        expect(response).to have_http_status(:success)
        expect(response).not_to redirect_to(discord_login_path)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug B4 + D (v2) — sign-out mints discord_signed_out; cleared after re-auth
  # ──────────────────────────────────────────────────────────────────────────
  describe "DELETE /sign_out" do
    before { login_discord_user! }

    it "sets the discord_signed_out session cookie so silent re-login is blocked until browser close" do
      delete sign_out_path
      expect(response.cookies["discord_signed_out"]).to be_present
    end

    it "does NOT clear the discord_uid cookie (only explicit Disconnect does that)" do
      delete sign_out_path
      # nil = untouched (preserved in browser); "" = explicitly deleted (Max-Age=0)
      expect(response.cookies["discord_uid"]).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug A — OAuth redirect URL must never contain prompt=consent
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /auth/discord OAuth redirect URL" do
    def force_full_oauth!
      login_discord_user!
      delete sign_out_path
    end

    context "when the user just signed out (discord_signed_out cookie present)" do
      before { force_full_oauth! }

      it "does NOT include prompt=consent in the authorization URL" do
        get discord_login_path
        expect(response).to be_redirect
        location = response.location
        expect(location).to include("discord.com")
        expect(location).not_to include("prompt=consent")
        expect(location).not_to include("prompt%3Dconsent")
      end

      it "includes all required OAuth 2.0 parameters" do
        get discord_login_path
        location = response.location
        expect(location).to include("response_type=code")
        expect(location).to include("scope=identify")
        expect(location).to include("state=")
      end
    end

    context "when a brand-new visitor has no session at all" do
      it "redirects to Discord without prompt=consent" do
        get discord_login_path
        expect(response).to be_redirect
        expect(response.location).to include("discord.com")
        expect(response.location).not_to include("prompt=consent")
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Returning users skip the Discord authorize screen (prompt=none on manual login)
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /auth/discord prompt=none for returning users" do
    it "requests prompt=none when the user has authorized before (discord_seen_before)" do
      get login_path
      cookies[:discord_seen_before] = generate_signed_cookie(:discord_seen_before, "1")

      get discord_login_path
      expect(response).to be_redirect
      expect(response.location).to include("discord.com/api/oauth2/authorize")
      expect(response.location).to include("prompt=none")
      expect(response.location).not_to include("prompt=consent")
    end

    it "requests prompt=none when a discord_uid cookie exists but its connection is gone (revoked) and the user clicked login" do
      get login_path
      cookies[:discord_uid] = generate_signed_cookie(:discord_uid, "111222333")

      # No UserDiscordConnection for that uid -> cookie silent path falls through.
      get discord_login_path, headers: { "HTTP_REFERER" => login_url }
      expect(response).to be_redirect
      expect(response.location).to include("discord.com/api/oauth2/authorize")
      expect(response.location).to include("prompt=none")
    end

    it "does NOT request prompt=none for a brand-new visitor (no cookies)" do
      get discord_login_path
      expect(response).to be_redirect
      expect(response.location).to include("discord.com/api/oauth2/authorize")
      expect(response.location).not_to include("prompt=none")
    end

    it "does NOT request prompt=none on a first-time signup with no prior Discord use" do
      get discord_login_path(signup: true)
      # Gated signup may redirect to account creation; only assert prompt when it reached Discord.
      if response.location.to_s.include?("discord.com")
        expect(response.location).not_to include("prompt=none")
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Discord token expiry must bound the app session (requirement: respect token expiry)
  # ──────────────────────────────────────────────────────────────────────────
  describe "Discord token expiry enforcement on protected pages" do
    it "allows access when the access token is still valid" do
      create(:user_discord_connection, user: discord_user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.from_now)
      sign_in discord_user

      get dashboard_path
      expect(response).to have_http_status(:success)
    end

    it "refreshes silently and allows access when the token is expired but refreshable" do
      create(:user_discord_connection, user: discord_user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.ago)
      allow_any_instance_of(UserDiscordConnection).to receive(:refresh!).and_return(true)
      sign_in discord_user

      get dashboard_path
      expect(response).to have_http_status(:success)
    end

    it "forces Discord re-auth when the token is expired and refresh is revoked" do
      create(:user_discord_connection, user: discord_user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.ago)
      allow_any_instance_of(UserDiscordConnection).to receive(:refresh!)
        .and_raise(Discord::DiscordTokenRevokedError, "revoked")
      sign_in discord_user

      get dashboard_path
      expect(response).to be_redirect
      expect(response.location).to include("/auth/discord")
      expect(response.location).to include("silent=1")
    end

    it "forces Discord re-auth when the token is expired and no refresh token exists" do
      create(:user_discord_connection, user: discord_user, discord_user_id: "111222333",
             refresh_token: nil, expires_at: 1.hour.ago)
      sign_in discord_user

      get dashboard_path
      expect(response).to be_redirect
      expect(response.location).to include("/auth/discord")
    end

    it "does not force re-auth for a Discord user without a stored connection (legacy state)" do
      sign_in discord_user

      get dashboard_path
      expect(response).to have_http_status(:success)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Bug B4 — silent login controlled by discord_signed_out cookie
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /auth/discord silent login" do
    let!(:connection) do
      create(:user_discord_connection,
             user: discord_user,
             discord_user_id: "111222333",
             access_token: "tok",
             refresh_token: "ref_tok",
             expires_at: 1.hour.from_now)
    end

    context "when discord_signed_out cookie is set (user just signed out)" do
      before do
        login_discord_user!
        delete sign_out_path
        expect(response.cookies["discord_signed_out"]).to be_present
      end

      it "skips silent login and redirects to Discord for full OAuth" do
        get discord_login_path
        expect(response).to be_redirect
        expect(response.location).to include("discord.com")
      end

      it "full OAuth URL still has no prompt=consent" do
        get discord_login_path
        expect(response.location).not_to include("prompt=consent")
      end
    end

    context "when discord_uid cookie is present and discord_signed_out is absent" do
      before do
        get login_path
        cookies[:discord_uid] = generate_signed_cookie(:discord_uid, discord_user.discord_user_id)
      end

      it "silently signs the user in and redirects to dashboard (no Discord.com round-trip)" do
        get discord_login_path
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end
end
