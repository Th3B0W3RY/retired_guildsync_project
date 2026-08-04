# frozen_string_literal: true

class AddPubliclyListedToGuilds < ActiveRecord::Migration[7.0]
  def change
    add_column :guilds, :publicly_listed, :boolean, default: true, null: false
    add_index  :guilds, :publicly_listed
  end
end
