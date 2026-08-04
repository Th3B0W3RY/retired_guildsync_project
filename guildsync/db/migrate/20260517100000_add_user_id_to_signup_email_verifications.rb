# frozen_string_literal: true

class AddUserIdToSignupEmailVerifications < ActiveRecord::Migration[8.0]
  def change
    add_reference :signup_email_verifications, :user, foreign_key: true, null: true
    add_index :signup_email_verifications, :user_id, unique: true,
      where: "verified_at IS NULL AND user_id IS NOT NULL",
      name: "index_signup_email_verifications_one_pending_per_user"
  end
end
