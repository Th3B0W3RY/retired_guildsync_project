# frozen_string_literal: true

class CreateAllianceLootRolls < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_loot_rolls do |t|
      t.bigint  :alliance_id,  null: false
      t.bigint  :creator_id,   null: false
      t.bigint  :winner_entry_id
      t.string  :title,        null: false
      t.text    :description
      t.integer :min_roll,     null: false, default: 1
      t.integer :max_roll,     null: false, default: 100
      t.boolean :anonymous,    null: false, default: false
      t.datetime :deadline_at
      t.integer :status,       null: false, default: 0  # 0=open, 1=closed

      t.timestamps
    end

    add_index :alliance_loot_rolls, :alliance_id
    add_index :alliance_loot_rolls, :creator_id
    add_index :alliance_loot_rolls, :status
    add_foreign_key :alliance_loot_rolls, :alliances
    add_foreign_key :alliance_loot_rolls, :users, column: :creator_id
  end
end
