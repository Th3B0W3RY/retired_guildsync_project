# frozen_string_literal: true

class CreateSignupEmailVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :signup_email_verifications do |t|
      t.string :email, null: false
      t.string :token_digest
      t.datetime :expires_at
      t.datetime :verified_at
      t.datetime :sent_at
      t.integer :send_count, null: false, default: 0
      t.string :last_sent_ip

      t.timestamps
    end

    add_index :signup_email_verifications, :email
    add_index :signup_email_verifications, :token_digest, unique: true
    add_index :signup_email_verifications, :verified_at
    add_index :signup_email_verifications, :expires_at
  end
end
