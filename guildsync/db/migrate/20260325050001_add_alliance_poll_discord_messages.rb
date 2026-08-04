# frozen_string_literal: true

class AddAlliancePollDiscordMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_poll_discord_messages do |t|
      t.references :alliance_poll, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.string :channel_id, null: false
      t.string :discord_message_id, null: false
      t.datetime :posted_at

      t.timestamps
    end

    add_index :alliance_poll_discord_messages,
              [ :alliance_poll_id, :guild_id ],
              unique: true,
              name: "idx_alliance_poll_discord_messages_poll_guild"
  end
end
