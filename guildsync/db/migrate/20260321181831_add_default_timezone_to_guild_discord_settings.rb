class AddDefaultTimezoneToGuildDiscordSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_discord_settings, :default_timezone, :string, default: "Eastern Time (US & Canada)"
  end
end
