# frozen_string_literal: true

class CreateAllianceMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_members do |t|
      t.bigint  :alliance_id, null: false
      t.bigint  :user_id,     null: false
      t.bigint  :guild_id,    null: false
      t.integer :role,        null: false, default: 0  # 0=member, 1=officer, 2=gm
      t.integer :status,      null: false, default: 0  # 0=active, 1=removed

      t.timestamps
    end

    add_index :alliance_members, :alliance_id
    add_index :alliance_members, :user_id
    add_index :alliance_members, :guild_id
    add_index :alliance_members, [ :alliance_id, :user_id ], unique: true
    add_foreign_key :alliance_members, :alliances
    add_foreign_key :alliance_members, :users
    add_foreign_key :alliance_members, :guilds
  end
end
