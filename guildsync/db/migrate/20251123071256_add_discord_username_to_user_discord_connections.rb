class AddDiscordUsernameToUserDiscordConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :user_discord_connections, :discord_username, :string, if_not_exists: true
  end
end
