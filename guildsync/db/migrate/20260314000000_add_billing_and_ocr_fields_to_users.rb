class AddBillingAndOcrFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :trial_started_at, :datetime, if_not_exists: true
    add_column :users, :trial_ends_at, :datetime, if_not_exists: true

    add_column :users, :billing_plan, :string, if_not_exists: true
    add_column :users, :ocr_requests_used, :integer, default: 0, null: false, if_not_exists: true
    add_column :users, :ocr_requests_limit, :integer, if_not_exists: true
    add_column :users, :billing_status, :string, if_not_exists: true

    add_index :users, :billing_plan, if_not_exists: true
    add_index :users, :billing_status, if_not_exists: true
    add_index :users, :trial_ends_at, if_not_exists: true
  end
end

