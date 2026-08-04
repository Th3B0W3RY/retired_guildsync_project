class CreateUserDiscordConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :user_discord_connections, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :discord_user_id, null: false
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :token_expires_at
      t.text :scopes

      t.timestamps
    end
    add_index :user_discord_connections, :discord_user_id, unique: true, if_not_exists: true
  end
end
