# frozen_string_literal: true

class ChangeUsersOtpSecretToTextForEncryption < ActiveRecord::Migration[8.0]
  def up
    change_column :users, :otp_secret, :text
  end

  def down
    change_column :users, :otp_secret, :string
  end
end
