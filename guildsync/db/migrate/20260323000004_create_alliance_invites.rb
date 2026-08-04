# frozen_string_literal: true

class CreateAllianceInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_invites do |t|
      t.bigint  :alliance_id,        null: false
      t.bigint  :guild_id,           null: false
      t.bigint  :invited_by_user_id, null: false
      t.integer :status,             null: false, default: 0  # 0=pending, 1=accepted, 2=declined

      t.timestamps
    end

    add_index :alliance_invites, :alliance_id
    add_index :alliance_invites, :guild_id
    add_index :alliance_invites, [ :alliance_id, :guild_id, :status ]
    add_foreign_key :alliance_invites, :alliances
    add_foreign_key :alliance_invites, :guilds
    add_foreign_key :alliance_invites, :users, column: :invited_by_user_id
  end
end
