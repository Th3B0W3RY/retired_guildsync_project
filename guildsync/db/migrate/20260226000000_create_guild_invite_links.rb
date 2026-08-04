# frozen_string_literal: true

class CreateGuildInviteLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_invite_links, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
