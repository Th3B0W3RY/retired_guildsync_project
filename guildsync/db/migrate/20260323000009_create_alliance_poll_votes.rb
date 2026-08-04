# frozen_string_literal: true

class CreateAlliancePollVotes < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_poll_votes do |t|
      t.bigint  :alliance_poll_id, null: false
      t.bigint  :user_id,          null: false
      t.integer :choice,           null: false  # 0=yes, 1=no, 2=maybe

      t.timestamps
    end

    add_index :alliance_poll_votes, :alliance_poll_id
    add_index :alliance_poll_votes, :user_id
    add_index :alliance_poll_votes, [ :alliance_poll_id, :user_id ], unique: true
    add_foreign_key :alliance_poll_votes, :alliance_polls
    add_foreign_key :alliance_poll_votes, :users
  end
end
