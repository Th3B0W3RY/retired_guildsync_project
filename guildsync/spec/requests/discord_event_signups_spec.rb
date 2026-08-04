# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DiscordEventSignups webhook", type: :request do
  let(:guild) { create(:guild) }
  let(:discord_event) { create(:discord_event, guild: guild) }
  let(:webhook_secret) { "discord-event-secret" }
  let(:headers) { { "X-Guildsync-Webhook-Secret" => webhook_secret } }

  around do |example|
    original_secret = ENV["DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET"]
    ENV["DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET"] = webhook_secret
    example.run
  ensure
    ENV["DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET"] = original_secret
  end

  describe "POST /discord/event_signups/webhook" do
    it "returns unauthorized when webhook secret header is missing" do
      post discord_event_signups_webhook_path, params: { event_id: discord_event.id, user_id: "discord_u1", role: "dps" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized when webhook secret is wrong (custom header)" do
      post discord_event_signups_webhook_path,
           params: { event_id: discord_event.id, user_id: "discord_u1", role: "dps" },
           headers: { "X-Guildsync-Webhook-Secret" => "wrong-secret" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized when webhook secret is wrong (Bearer token)" do
      post discord_event_signups_webhook_path,
           params: { event_id: discord_event.id, user_id: "discord_u1", role: "dps" },
           headers: { "Authorization" => "Bearer wrong-secret" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "authenticates via Authorization Bearer token" do
      post discord_event_signups_webhook_path,
           params: { event_id: discord_event.id, user_id: "discord_u1", role: "dps", username: "PlayerOne" },
           headers: { "Authorization" => "Bearer #{webhook_secret}" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "returns localized bad request when parameters are missing" do
      post discord_event_signups_webhook_path, params: { event_id: discord_event.id }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq(
        I18n.t("controllers.discord_event_signups.webhook.missing_required_parameters")
      )
    end

    it "returns localized not found when event id is unknown" do
      post discord_event_signups_webhook_path, params: {
        event_id: 9_999_999,
        user_id: "discord_u1",
        role: "dps"
      }, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq(
        I18n.t("controllers.discord_event_signups.webhook.event_not_found")
      )
    end

    it "returns localized bad request when role is invalid" do
      post discord_event_signups_webhook_path, params: {
        event_id: discord_event.id,
        user_id: "discord_u1",
        role: "invalid_role"
      }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq(
        I18n.t("controllers.discord_event_signups.webhook.invalid_role")
      )
    end

    it "creates signup and returns success for valid payload" do
      expect {
        post discord_event_signups_webhook_path, params: {
          event_id: discord_event.id,
          user_id: "discord_u1",
          role: "dps",
          username: "PlayerOne"
        }, headers: headers
      }.to change(DiscordEventSignup, :count).by(1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["signups_count"]).to eq(1)
    end
  end
end
