# frozen_string_literal: true

class AddSignupIpToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :signup_ip, :string, limit: 45, null: true unless column_exists?(:users, :signup_ip)
    add_index :users, :signup_ip, if_not_exists: true
  end
end
