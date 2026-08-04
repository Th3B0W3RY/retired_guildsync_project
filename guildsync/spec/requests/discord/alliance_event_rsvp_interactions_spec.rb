# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Discord alliance event RSVP interactions", type: :request do
  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }
  let(:event) { create(:alliance_event, alliance: alliance, created_by: owner) }
  let(:discord_user_id) { "998877665544332211" }
  let(:interaction_token) { "test_alliance_rsvp_token" }

  def interaction_payload(custom_id:, user_id:)
    {
      type: 3,
      token: interaction_token,
      id: "abc123",
      data: { custom_id: custom_id, component_type: 2 },
      member: {
        nick: "ServerNick",
        user: {
          id: user_id,
          username: "tester",
          discriminator: "1234"
        }
      }
    }
  end

  before do
    allow_any_instance_of(DiscordWebhooksController).to receive(:verify_discord_signature).and_return(true)
    allow_any_instance_of(DiscordWebhooksController).to receive(:send_followup_message).and_return(nil)
    create(:alliance_guild, alliance: alliance, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: alliance, user: owner, guild: guild, role: :gm, status: :active)
  end

  it "shows status selection for alliance role signup buttons" do
    create(:user_discord_connection, user: owner, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(custom_id: "alliance_event_signup_#{event.id}_dps", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["type"]).to eq(5)
  end

  it "creates signup status for active alliance members" do
    create(:user_discord_connection, user: owner, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(custom_id: "alliance_event_status_#{event.id}_dps_on_time_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["type"]).to eq(5)

    sleep 0.05
    signup = AllianceEventDiscordSignup.find_by(alliance_event: event, discord_user_id: discord_user_id)
    expect(signup).to be_present
    expect(signup.role).to eq("dps")
    expect(signup.status).to eq("on_time")
    expect(signup.discord_display_name).to eq("ServerNick")
  end

  it "does not create signup for linked users who are not active alliance members" do
    outsider = create(:user, :discord_auth)
    create(:user_discord_connection, user: outsider, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(custom_id: "alliance_event_status_#{event.id}_dps_on_time_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    expect(AllianceEventDiscordSignup.where(alliance_event: event, discord_user_id: discord_user_id).count).to eq(0)
  end

  it "does not create signup for invalid status" do
    create(:user_discord_connection, user: owner, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(custom_id: "alliance_event_status_#{event.id}_dps_unknown_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    expect(AllianceEventDiscordSignup.where(alliance_event: event, discord_user_id: discord_user_id).count).to eq(0)
  end

  it "creates a Discord-only signup for unlinked users (no GuildSync account linked)" do
    post "/discord/webhooks",
         params: interaction_payload(custom_id: "alliance_event_status_#{event.id}_dps_on_time_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    signup = AllianceEventDiscordSignup.find_by(alliance_event: event, discord_user_id: discord_user_id)
    expect(signup).to be_present
    expect(signup.status).to eq("on_time")
    expect(signup.role).to eq("dps")
  end
end
