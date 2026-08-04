# frozen_string_literal: true

class CreateAllianceActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_activity_logs do |t|
      t.references :alliance, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :guild, null: true, foreign_key: true
      t.string :action_type, null: false
      t.string :description, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :alliance_activity_logs, [ :alliance_id, :created_at ], order: { created_at: :desc }
    add_index :alliance_activity_logs, [ :alliance_id, :action_type ]
  end
end
