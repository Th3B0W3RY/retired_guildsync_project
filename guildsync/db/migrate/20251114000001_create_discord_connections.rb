class CreateDiscordConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_connections, if_not_exists: true do |t|
      # Disable auto index to avoid duplicate index conflicts
      t.references :user, null: false, foreign_key: true, index: false

      t.string :discord_user_id, null: false
      t.string :discord_username
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :expires_at

      t.timestamps
    end

    # Unique Discord account per platform user
    add_index :discord_connections, :discord_user_id, unique: true, if_not_exists: true
    
    # Unique 1:1 mapping between local user and Discord connection
    add_index :discord_connections, :user_id, unique: true, if_not_exists: true
  end
end
