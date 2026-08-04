# frozen_string_literal: true

# Shared context for stubbing Discord API requests
# Include this in tests that interact with Discord API
RSpec.shared_context "Discord API stubs" do
  let(:fake_bot_token) { "fake_bot_token" }
  let(:fake_client_id) { "fake_client_id" }
  let(:fake_public_key) { nil } # Will skip signature verification in test

  before do
    # Stub environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(fake_bot_token)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return(fake_client_id)
    allow(ENV).to receive(:[]).with("DISCORD_PUBLIC_KEY").and_return(fake_public_key)

    # Stub Discord webhook followup messages (used by send_followup_message)
    # This matches the pattern: POST https://discord.com/api/v10/webhooks/{application_id}/{interaction_token}
    # Use a more flexible regex that matches any client_id and any interaction token
    # Match any body content and any bot token since different tests may use different tokens
    stub_request(:post, %r{https://discord\.com/api/v10/webhooks/[^/]+/.+})
      .with(
        headers: {
          "Authorization" => /^Bot .+/,
          "Content-Type" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {}.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord message updates (used by DiscordService#update_message)
    stub_request(:patch, %r{https://discord\.com/api/v10/channels/\d+/messages/\d+})
      .with(
        headers: {
          "Authorization" => "Bot #{fake_bot_token}",
          "Content-Type" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {}.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord channel message creation
    stub_request(:post, %r{https://discord\.com/api/v10/channels/\d+/messages})
      .with(
        headers: {
          "Authorization" => "Bot #{fake_bot_token}",
          "Content-Type" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: { id: "fake_message_id" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord scheduled events (POST - create)
    stub_request(:post, %r{https://discord\.com/api/v10/guilds/\d+/scheduled-events})
      .with(
        headers: {
          "Authorization" => "Bot #{fake_bot_token}",
          "Content-Type" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: { id: "fake_scheduled_event_id" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord scheduled events (GET - list)
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/\d+/scheduled-events})
      .with(
        headers: {
          "Authorization" => "Bot #{fake_bot_token}"
        }
      )
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord guild info
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/\d+})
      .with(
        headers: {
          "Authorization" => "Bot #{fake_bot_token}"
        }
      )
      .to_return(
        status: 200,
        body: { id: "123456789012345678", name: "Test Server" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end

