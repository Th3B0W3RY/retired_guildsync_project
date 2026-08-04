# frozen_string_literal: true

class CreateOcrUsageChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :ocr_usage_changes, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :delta, null: false
      t.string :reason, null: false
      t.string :admin_email, null: false
      t.integer :before_used_period
      t.integer :after_used_period
      t.boolean :from_admin_panel, default: true, null: false
      t.string :action_type

      t.timestamps
    end

    add_index :ocr_usage_changes, :created_at, if_not_exists: true
    add_index :ocr_usage_changes, [ :user_id, :created_at ], if_not_exists: true
  end
end
