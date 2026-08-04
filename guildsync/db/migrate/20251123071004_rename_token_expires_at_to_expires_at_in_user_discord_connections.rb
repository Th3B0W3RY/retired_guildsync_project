class RenameTokenExpiresAtToExpiresAtInUserDiscordConnections < ActiveRecord::Migration[8.0]
  def change
    return unless column_exists?(:user_discord_connections, :token_expires_at)
    rename_column :user_discord_connections, :token_expires_at, :expires_at
  end
end
