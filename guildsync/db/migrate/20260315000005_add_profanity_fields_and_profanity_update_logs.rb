# frozen_string_literal: true

class AddProfanityFieldsAndProfanityUpdateLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :blocked_words, :source, :string
    add_column :blocked_words, :last_seen_at, :datetime
    add_column :blocked_words, :deactivated_at, :datetime

    create_table :profanity_update_logs do |t|
      t.datetime :timestamp, null: false
      t.jsonb :sources_checked, default: []
      t.integer :new_words_added, default: 0, null: false
      t.integer :words_removed, default: 0, null: false
      t.integer :total_words, default: 0, null: false
      t.jsonb :errors, default: []
      t.timestamps
    end
    add_index :profanity_update_logs, :created_at
  end
end
