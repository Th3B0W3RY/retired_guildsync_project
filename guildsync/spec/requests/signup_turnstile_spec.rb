# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Signup with Turnstile enforced", type: :request do
  let(:site_key) { "1x00000000000000000000AA" }
  let(:secret_key) { "1x0000000000000000000000000000000AA" }
  let(:client_id) { "test_client_id_123" }
  let(:client_secret) { "test_client_secret_456" }

  before do
    ENV["TURNSTILE_STRICT_IN_TEST"] = "1"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(site_key)
    allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(secret_key)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_SECRET").and_return(client_secret)

    stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })
  end

  after do
    ENV.delete("TURNSTILE_STRICT_IN_TEST")
  end

  describe "POST /create_account" do
    let(:pricing_plan) { create(:pricing_plan, name: "Free", max_guilds: 1) }

    it "rejects verification without captcha token" do
      expect do
        post create_account_path, params: { email: "turnstile_gate@example.com" }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates a pending email verification when captcha token is present" do
      expect do
        post create_account_path, params: {
          email: "turnstile_ok@example.com",
          "cf-turnstile-response" => "test-token"
        }
      end.to change(SignupEmailVerification, :count).by(1)

      expect(response).to redirect_to(create_account_sent_path)
    end

    it "rejects verification when Cloudflare returns success false" do
      stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
        .to_return(status: 200, body: { success: false, "error-codes" => [ "invalid-input-response" ] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect do
        post create_account_path, params: {
          email: "turnstile_bad@example.com",
          "cf-turnstile-response" => "bad-token"
        }
      end.not_to change(SignupEmailVerification, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/auth/sign_up" do
    let!(:free_plan) do
      create(:pricing_plan,
             name: "Free",
             price: 0,
             price_display: "$0",
             period: "forever",
             max_guilds: 1,
             max_members_per_guild: 10,
             active: true,
             display_order: 1)
    end

    it "returns 422 without captcha token" do
      expect do
        post "/api/v1/auth/sign_up",
             params: {
               user: {
                 email: "api_gate@example.com",
                 username: "apigate",
                 password: "password123",
                 password_confirmation: "password123"
               }
             },
             as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to be_present
    end

    it "creates user with cf_turnstile_response" do
      post "/api/v1/auth/sign_up",
           params: {
             cf_turnstile_response: "tok",
             user: {
               email: "api_ok@example.com",
               username: "apiok",
               password: "password123",
               password_confirmation: "password123"
             }
           },
           as: :json

      expect(response).to have_http_status(:created)
      expect(User.find_by(email: "api_ok@example.com")).to be_present
    end

    it "returns 422 when Cloudflare rejects the token" do
      stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
        .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })

      expect do
        post "/api/v1/auth/sign_up",
             params: {
               cf_turnstile_response: "bad",
               user: {
                 email: "api_bad_tok@example.com",
                 username: "apibadtok",
                 password: "password123",
                 password_confirmation: "password123"
               }
             },
             as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "Discord OAuth start with signup" do
    before do
      allow_any_instance_of(DiscordUserOAuthService).to receive(:client_id).and_return(client_id)
      allow_any_instance_of(DiscordUserOAuthService).to receive(:client_secret).and_return(client_secret)
      allow_any_instance_of(DiscordUserOAuthService).to receive(:authorization_url).and_return(
        "https://discord.com/api/oauth2/authorize?client_id=#{client_id}"
      )
    end

    it "redirects GET with signup to the email verification flow" do
      get "/auth/discord", params: { signup: true }
      expect(response).to redirect_to(create_account_path)
    end

    it "blocks POST with signup until email verification and backup code confirmation are complete" do
      post "/auth/discord", params: { signup: true, "cf-turnstile-response" => "tok" }
      expect(response).to redirect_to(create_account_path)
    end
  end
end
