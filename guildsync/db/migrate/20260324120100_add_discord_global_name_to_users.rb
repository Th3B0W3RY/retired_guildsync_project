# frozen_string_literal: true

class AddDiscordGlobalNameToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :discord_global_name, :string
  end
end
