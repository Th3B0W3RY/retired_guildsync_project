# frozen_string_literal: true

class AddAccountClosureSoftCompletedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :account_closure_soft_completed_at, :datetime
    add_index :users, :account_closure_soft_completed_at
  end
end
