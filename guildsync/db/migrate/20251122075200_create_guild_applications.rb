class CreateGuildApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_applications, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.string :discord_username
      t.integer :status, default: 0, null: false
      t.text :message

      t.timestamps
    end
    
    add_index :guild_applications, [:user_id, :guild_id], unique: true, name: 'index_guild_applications_on_user_and_guild', if_not_exists: true
  end
end
