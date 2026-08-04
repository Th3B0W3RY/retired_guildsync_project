# frozen_string_literal: true

class CreateGuildActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_activity_logs, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :action_type, null: false
      t.string :description, null: false
      t.references :subject, polymorphic: true, null: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :guild_activity_logs, [ :guild_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :guild_activity_logs, [ :guild_id, :action_type ], if_not_exists: true
    add_index :guild_activity_logs, [ :guild_id, :user_id ], if_not_exists: true
    add_index :guild_activity_logs, :created_at, if_not_exists: true
  end
end
