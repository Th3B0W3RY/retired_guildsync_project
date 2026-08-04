class CreateGuildDiscordSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_discord_settings, if_not_exists: true do |t|
      # Disable auto index to avoid duplicate index conflicts
      t.references :guild, null: false, foreign_key: true, index: false

      t.string :discord_guild_id, null: false
      t.string :discord_guild_name
      t.text :bot_token
      t.string :events_channel_id
      t.string :guild_battles_channel_id
      t.string :gear_channel_id
      t.datetime :connected_at

      t.timestamps
    end

    # Unique Discord server per guild
    add_index :guild_discord_settings, :discord_guild_id, unique: true, if_not_exists: true
    
    # Unique 1:1 mapping between guild and Discord settings
    add_index :guild_discord_settings, :guild_id, unique: true, if_not_exists: true
  end
end
