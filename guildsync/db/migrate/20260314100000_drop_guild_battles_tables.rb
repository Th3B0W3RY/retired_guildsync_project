# frozen_string_literal: true

class DropGuildBattlesTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :guild_battle_messages, if_exists: true
    drop_table :guild_battles, if_exists: true
    remove_column :guild_discord_settings, :guild_battles_channel_id if column_exists?(:guild_discord_settings, :guild_battles_channel_id)
  end

  def down
    add_column :guild_discord_settings, :guild_battles_channel_id, :string, if_not_exists: true unless column_exists?(:guild_discord_settings, :guild_battles_channel_id)
    # Recreating guild_battles and guild_battle_messages would require the full schema from original migrations; leave down as no-op for drop-only removal
  end
end
