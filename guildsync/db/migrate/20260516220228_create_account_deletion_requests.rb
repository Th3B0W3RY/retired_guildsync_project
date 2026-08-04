# frozen_string_literal: true

class CreateAccountDeletionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :account_deletion_requests do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :code_digest
      t.datetime :expires_at
      t.datetime :sent_at
      t.datetime :consumed_at
      t.integer :attempts_count, null: false, default: 0
      t.string :last_sent_ip

      t.timestamps
    end

    change_table :users, bulk: true do |t|
      t.datetime :account_closed_at
      t.datetime :account_deletion_started_at
    end

    add_index :users, :account_closed_at
  end
end
