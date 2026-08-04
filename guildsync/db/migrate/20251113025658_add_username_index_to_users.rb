# frozen_string_literal: true

class AddUsernameIndexToUsers < ActiveRecord::Migration[8.0]
  def change
    # Add unique index on username for performance and to enforce uniqueness at DB level
    # Username already has uniqueness validation in the model, but DB index ensures consistency
    add_index :users, :username, unique: true, if_not_exists: true
  end
end
