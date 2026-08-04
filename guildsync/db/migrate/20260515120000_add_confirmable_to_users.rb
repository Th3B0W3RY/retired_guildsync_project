# frozen_string_literal: true

class AddConfirmableToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # large backfill: avoid holding one exclusive lock for entire table

  def up
    unless column_exists?(:users, :confirmation_token)
      add_column :users, :confirmation_token, :string
    end
    unless column_exists?(:users, :confirmed_at)
      add_column :users, :confirmed_at, :datetime
    end
    unless column_exists?(:users, :confirmation_sent_at)
      add_column :users, :confirmation_sent_at, :datetime
    end
    unless column_exists?(:users, :unconfirmed_email)
      add_column :users, :unconfirmed_email, :string
    end

    unless index_exists?(:users, :confirmation_token)
      add_index :users, :confirmation_token, unique: true, algorithm: :concurrently
    end

    say_with_time "Backfill confirmed_at for existing users" do
      now = Time.zone.now
      User.unscoped.in_batches(of: 5_000) do |batch|
        batch.where(confirmed_at: nil).update_all(confirmed_at: now)
      end
    end
  end

  def down
    remove_index :users, :confirmation_token, algorithm: :concurrently, if_exists: true
    remove_column :users, :unconfirmed_email
    remove_column :users, :confirmation_sent_at
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_token
  end
end
