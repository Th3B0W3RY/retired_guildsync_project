# frozen_string_literal: true

class CreateOcrRequestsAndAbuseTables < ActiveRecord::Migration[8.0]
  def change
    create_table :ocr_requests, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 500
      t.datetime :created_at, null: false
    end
    add_index :ocr_requests, [ :user_id, :created_at ], if_not_exists: true
    add_index :ocr_requests, :ip_address, if_not_exists: true
    add_index :ocr_requests, :created_at, if_not_exists: true

    create_table :ocr_denials, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :reason, null: false
      t.integer :current_usage, null: false
      t.integer :limit, null: false
      t.integer :hard_stop, null: false
      t.datetime :created_at, null: false
    end
    add_index :ocr_denials, [ :user_id, :created_at ], if_not_exists: true

    create_table :abuse_flags, if_not_exists: true do |t|
      t.string :target_type, null: false
      t.string :target_value, null: false
      t.string :reason, null: false
      t.integer :severity, default: 1, null: false
      t.datetime :created_at, null: false
    end
    add_index :abuse_flags, [ :target_type, :target_value ], if_not_exists: true
    add_index :abuse_flags, :created_at, if_not_exists: true
  end
end
