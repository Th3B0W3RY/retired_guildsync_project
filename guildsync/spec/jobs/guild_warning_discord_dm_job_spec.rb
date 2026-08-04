# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildWarningDiscordDmJob, type: :job do
  it "sends a discord DM when user and guild are connected" do
    guild = create(:guild)
    user = create(:user)
    create(:guild_member, guild: guild, user: user, status: :active)
    create(:guild_discord_setting, guild: guild, bot_token: "bot-token")
    create(:user_discord_connection, user: user, discord_user_id: "123", discord_username: "member#1234")

    discord_service = instance_double(DiscordService, send_dm: true)
    allow(DiscordService).to receive(:new).and_return(discord_service)

    described_class.perform_now(guild.id, user.id, "Warning reason", 2)

    expect(discord_service).to have_received(:send_dm).with("123", include("Warning reason"))
  end

  it "does not call Discord when the user has no linked Discord account" do
    guild = create(:guild)
    user = create(:user)
    create(:guild_discord_setting, guild: guild, bot_token: "bot-token")

    expect(DiscordService).not_to receive(:new)

    described_class.perform_now(guild.id, user.id, "Warning reason", 1)
  end
end
