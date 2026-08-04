# frozen_string_literal: true

class AddAccountCreationStateToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :registration_completed_at, :datetime
    add_column :users, :signup_email_verified_at, :datetime
    add_column :users, :backup_code_acknowledged_at, :datetime
    add_column :users, :backup_code_regenerated_at, :datetime

    add_index :users, :registration_completed_at
    add_index :users, :signup_email_verified_at
    add_index :users, :backup_code_regenerated_at

    execute <<~SQL.squish
      UPDATE users
      SET registration_completed_at = COALESCE(created_at, NOW())
      WHERE registration_completed_at IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE users
      SET signup_email_verified_at = COALESCE(created_at, NOW())
      WHERE signup_email_verified_at IS NULL
        AND email NOT LIKE '%@discord.guildsync.local'
    SQL
  end

  def down
    remove_index :users, :backup_code_regenerated_at, if_exists: true
    remove_index :users, :signup_email_verified_at, if_exists: true
    remove_index :users, :registration_completed_at, if_exists: true

    remove_column :users, :backup_code_regenerated_at
    remove_column :users, :backup_code_acknowledged_at
    remove_column :users, :signup_email_verified_at
    remove_column :users, :registration_completed_at
  end
end
