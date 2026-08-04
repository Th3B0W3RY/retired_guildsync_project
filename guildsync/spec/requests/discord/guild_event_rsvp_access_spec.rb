# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Discord guild event RSVP access", type: :request do
  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:discord_connection) { create(:discord_connection, guild: guild, user: owner) }
  let(:event) { create(:discord_event, guild: guild, discord_connection: discord_connection) }
  let(:interaction_token) { "guild_event_rsvp_token" }
  let(:discord_user_id) { "112233445566778899" }

  def interaction_payload(custom_id:, user_id:, nick: nil, username: "tester", discriminator: "1234")
    {
      type: 3,
      token: interaction_token,
      id: "abc123",
      data: { custom_id: custom_id, component_type: 2 },
      member: {
        nick: nick,
        user: {
          id: user_id,
          username: username,
          discriminator: discriminator
        }
      }
    }
  end

  before do
    allow_any_instance_of(DiscordWebhooksController).to receive(:verify_discord_signature).and_return(true)
    allow_any_instance_of(DiscordWebhooksController).to receive(:send_followup_message).and_return(nil)
  end

  it "stores Discord server nickname as signup display name" do
    create(:user_discord_connection, user: owner, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(
           custom_id: "event_status_#{event.id}_dps_on_time_#{discord_user_id}",
           user_id: discord_user_id,
           nick: "ServerRaidNick"
         ).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    sleep 0.05

    signup = DiscordEventSignup.find_by(discord_event: event, discord_user_id: discord_user_id)
    expect(signup).to be_present
    expect(signup.discord_display_name).to eq("ServerRaidNick")
  end

  it "does not create signup for unlinked users" do
    post "/discord/webhooks",
         params: interaction_payload(custom_id: "event_status_#{event.id}_dps_on_time_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    expect(DiscordEventSignup.where(discord_event: event, discord_user_id: discord_user_id).count).to eq(0)
  end

  it "does not create signup for linked users outside the guild" do
    outsider = create(:user, :discord_auth)
    create(:user_discord_connection, user: outsider, discord_user_id: discord_user_id)

    post "/discord/webhooks",
         params: interaction_payload(custom_id: "event_status_#{event.id}_dps_on_time_#{discord_user_id}", user_id: discord_user_id).to_json,
         headers: { "Content-Type" => "application/json", "X-Signature-Ed25519" => "0" * 128, "X-Signature-Timestamp" => Time.current.to_i.to_s }

    expect(response).to have_http_status(:success)
    expect(DiscordEventSignup.where(discord_event: event, discord_user_id: discord_user_id).count).to eq(0)
  end
end
