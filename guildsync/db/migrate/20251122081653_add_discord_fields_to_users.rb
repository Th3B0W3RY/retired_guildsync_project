class AddDiscordFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :discord_user_id, :string, if_not_exists: true
    add_column :users, :discord_username, :string, if_not_exists: true
    add_column :users, :discord_avatar_url, :string, if_not_exists: true
    add_column :users, :discord_connected, :boolean, default: false, null: false, if_not_exists: true
    add_column :users, :auth_method, :integer, default: 0, null: false, if_not_exists: true
    
    add_index :users, :discord_user_id, unique: true, where: "discord_user_id IS NOT NULL", if_not_exists: true
  end
end
