class CreateDiscordEventSignups < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_event_signups, if_not_exists: true do |t|
      t.references :discord_event, null: false, foreign_key: true
      t.string :discord_user_id, null: false
      t.string :discord_username
      t.integer :role, null: false
      t.timestamps
    end

    add_index :discord_event_signups, [:discord_event_id, :discord_user_id, :role], unique: true, name: 'index_discord_event_signups_unique', if_not_exists: true
    add_index :discord_event_signups, :discord_user_id, if_not_exists: true
  end
end
