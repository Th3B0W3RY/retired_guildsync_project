class AddAllianceDiscordSignupParityTables < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_event_discord_signups do |t|
      t.references :alliance_event, null: false, foreign_key: true
      t.string :discord_user_id, null: false
      t.string :discord_username
      t.string :discord_display_name
      t.integer :role, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :alliance_event_discord_signups,
      [ :alliance_event_id, :discord_user_id ],
      unique: true,
      name: "idx_alliance_event_discord_signups_event_user"

    create_table :alliance_event_discord_messages do |t|
      t.references :alliance_event, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.string :channel_id, null: false
      t.string :discord_message_id, null: false
      t.datetime :posted_at, null: false

      t.timestamps
    end

    add_index :alliance_event_discord_messages,
      [ :alliance_event_id, :guild_id ],
      unique: true,
      name: "idx_alliance_event_discord_messages_event_guild"
  end
end
