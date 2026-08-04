class AddDiscordIdToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :discord_id, :string, if_not_exists: true
    add_index :guilds, :discord_id, if_not_exists: true
  end
end
