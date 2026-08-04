class CreateDiscordEventParticipations < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_event_participations, if_not_exists: true do |t|
      t.references :event, null: false, foreign_key: true
      t.string :discord_user_id, null: false
      t.string :discord_username
      t.string :discord_message_id

      t.timestamps
    end

    add_index :discord_event_participations, [ :event_id, :discord_user_id ], unique: true, name: 'index_discord_event_participations_unique', if_not_exists: true
  end
end
