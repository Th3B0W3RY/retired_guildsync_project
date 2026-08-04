class AddLootRollsChannelToGuildDiscordSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_discord_settings, :loot_rolls_channel_id, :string, if_not_exists: true
  end
end
