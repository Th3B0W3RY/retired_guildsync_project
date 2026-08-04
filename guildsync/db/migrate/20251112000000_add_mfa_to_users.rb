class AddMfaToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :otp_secret, :string, if_not_exists: true
    add_column :users, :mfa_enabled, :boolean, default: false, null: false, if_not_exists: true
    add_column :users, :mfa_verified, :boolean, default: false, null: false, if_not_exists: true

    add_index :users, :mfa_enabled, if_not_exists: true
  end
end
