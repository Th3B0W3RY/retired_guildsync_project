# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordBotService, type: :service do
  let(:bot_service) { described_class.allocate }
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner, discord_id: nil) }
  let!(:guild_discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_id: "SERVER_123") }
  let!(:synced_role) { create(:discord_role_sync, guild: guild, role_id: "11122233344455", role_name: "Raiders") }
  let!(:react_role) do
    create(:react_role, guild: guild, position: 1,
           role_id: synced_role.role_id, role_name: synced_role.role_name,
           emoji_name: "🔥", is_custom_emoji: false,
           message_id: "MSG_123", channel_id: "CHANNEL_123")
  end

  before do
    bot_service.instance_variable_set(:@discord_logger, Logger.new(nil))
  end

  describe "#handle_react_role_event" do
    let(:server) { instance_double("DiscordServer", id: "SERVER_123") }
    let(:emoji) { instance_double("DiscordEmoji", name: "🔥", id: nil) }
    let(:user) { instance_double("DiscordUser", id: "USER_777") }
    let(:event) do
      instance_double(
        "ReactionEvent",
        message_id: "MSG_123",
        server: server,
        user: user,
        emoji: emoji
      )
    end

    it "uses gateway message_id and delegates add with guild-id fallback" do
      service_double = instance_double(DiscordReactRolesService)
      expect(DiscordReactRolesService).to receive(:new).with(guild).and_return(service_double)
      expect(service_double).to receive(:handle_reaction_add).with("USER_777", "MSG_123", "🔥", nil)

      bot_service.send(:handle_react_role_event, event, :add)
    end

    it "does not delegate when event server_id mismatches resolved guild id" do
      mismatched_server = instance_double("DiscordServer", id: "SERVER_OTHER")
      mismatched_event = instance_double(
        "ReactionEvent",
        message_id: "MSG_123",
        server: mismatched_server,
        user: user,
        emoji: emoji
      )

      expect(DiscordReactRolesService).not_to receive(:new)
      bot_service.send(:handle_react_role_event, mismatched_event, :add)
    end
  end
end
