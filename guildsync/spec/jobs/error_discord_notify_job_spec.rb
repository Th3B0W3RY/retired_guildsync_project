# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorDiscordNotifyJob, type: :job do
  let(:log) do
    ErrorLog.create!(
      error_class: "ArgumentError",
      message: "bad arg",
      occurred_at: Time.current,
      severity: "high"
    )
  end

  it "does nothing when error log id is missing" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "skips DMs when DISCORD_BOT_TOKEN is blank" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return(nil)

    expect(DiscordService).not_to receive(:new)

    described_class.perform_now(log.id)
  end

  it "sends DM to users listed in SiteSetting with linked Discord" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("bot-token")
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_URL").and_return(nil)

    user = create(:user, username: "err_ops")
    create(:user_discord_connection, user: user, discord_user_id: "123456789012345678")
    allow(SiteSetting).to receive(:error_notify_discord_usernames).and_return([ "err_ops" ])

    discord_service = instance_double(DiscordService, send_dm: true)
    allow(DiscordService).to receive(:new).with(bot_token: "bot-token").and_return(discord_service)

    described_class.perform_now(log.id)

    expect(discord_service).to have_received(:send_dm).with(
      "123456789012345678",
      a_string_including("ArgumentError", "bad arg")
    )
  end

  it "posts to webhook when ERROR_NOTIFY_DISCORD_WEBHOOK_URL is set" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(nil)
    webhook = "https://discord.com/api/webhooks/1/2"
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return(webhook)

    expect(RestClient).to receive(:post).with(
      webhook,
      a_string_including("ArgumentError"),
      hash_including("Content-Type" => "application/json")
    )

    described_class.perform_now(log.id)
  end

  it "rescues webhook failures without raising" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://example.com/hook")

    allow(RestClient).to receive(:post).and_raise(StandardError, "network")

    expect { described_class.perform_now(log.id) }.not_to raise_error
  end

  it "rescues DM failures without raising" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("bot-token")
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_URL").and_return(nil)

    user = create(:user, username: "err_ops_two")
    create(:user_discord_connection, user: user, discord_user_id: "999")
    allow(SiteSetting).to receive(:error_notify_discord_usernames).and_return([ "err_ops_two" ])

    discord_service = instance_double(DiscordService)
    allow(discord_service).to receive(:send_dm).and_raise(StandardError, "discord down")
    allow(DiscordService).to receive(:new).with(bot_token: "bot-token").and_return(discord_service)

    expect { described_class.perform_now(log.id) }.not_to raise_error
  end
end
