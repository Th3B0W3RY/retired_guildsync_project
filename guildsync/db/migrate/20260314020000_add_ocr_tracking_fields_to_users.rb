# frozen_string_literal: true

class AddOcrTrackingFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :ocr_billing_plan, :string, if_not_exists: true
    add_column :users, :ocr_last_reset_at, :datetime, if_not_exists: true
    add_column :users, :ocr_hard_locked, :boolean, default: false, null: false, if_not_exists: true
    add_column :users, :ocr_unlocked, :boolean, default: false, null: false, if_not_exists: true
    add_column :users, :trial_expired_at, :datetime, if_not_exists: true
    add_column :users, :ocr_notes, :text, if_not_exists: true
    add_column :users, :ocr_requests_used_this_period, :integer, default: 0, null: false, if_not_exists: true

    add_index :users, :ocr_billing_plan, if_not_exists: true
    add_index :users, :ocr_hard_locked, if_not_exists: true
    add_index :users, :ocr_unlocked, if_not_exists: true
    add_index :users, :trial_expired_at, if_not_exists: true
  end
end
