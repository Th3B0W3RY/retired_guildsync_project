# frozen_string_literal: true

class CreateAlliancePolls < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_polls do |t|
      t.bigint  :alliance_id, null: false
      t.bigint  :creator_id,  null: false
      t.string  :title,       null: false
      t.text    :description
      t.datetime :deadline,   null: false
      t.boolean :anonymous,   null: false, default: false

      t.timestamps
    end

    add_index :alliance_polls, :alliance_id
    add_index :alliance_polls, :creator_id
    add_index :alliance_polls, :deadline
    add_foreign_key :alliance_polls, :alliances
    add_foreign_key :alliance_polls, :users, column: :creator_id
  end
end
