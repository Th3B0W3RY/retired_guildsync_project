# frozen_string_literal: true

class AddAllianceChannelsToGuildDiscordSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_discord_settings, :alliance_events_channel_id, :string
    add_column :guild_discord_settings, :alliance_polls_channel_id, :string
    add_column :guild_discord_settings, :alliance_loot_rolls_channel_id, :string
    add_column :guild_discord_settings, :alliance_invites_channel_id, :string
  end
end
