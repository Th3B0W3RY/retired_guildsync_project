# frozen_string_literal: true

class AddAccountDataPurgedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :account_data_purged_at, :datetime
    add_index :users, :account_data_purged_at
  end
end
