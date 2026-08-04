# frozen_string_literal: true

class CreateAllianceDisbandVotes < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_disband_votes do |t|
      t.bigint  :alliance_id, null: false
      t.bigint  :user_id,     null: false
      t.bigint  :guild_id,    null: false
      t.boolean :vote,        null: false, default: false  # true = vote to disband

      t.timestamps
    end

    add_index :alliance_disband_votes, :alliance_id
    add_index :alliance_disband_votes, [ :alliance_id, :guild_id ], unique: true
    add_foreign_key :alliance_disband_votes, :alliances
    add_foreign_key :alliance_disband_votes, :users
    add_foreign_key :alliance_disband_votes, :guilds
  end
end
