class CreateDiscordEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_events, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :discord_connection, null: false, foreign_key: true
      t.string :discord_event_id, null: false
      t.string :discord_message_id
      t.string :channel_id, null: false
      t.string :title, null: false
      t.text :description
      t.string :event_type
      t.datetime :scheduled_at, null: false
      t.integer :max_participants
      t.jsonb :role_categories, default: []
      t.timestamps
    end

    add_index :discord_events, :discord_event_id, unique: true, if_not_exists: true
    add_index :discord_events, :discord_message_id, if_not_exists: true
    add_index :discord_events, :channel_id, if_not_exists: true
  end
end
