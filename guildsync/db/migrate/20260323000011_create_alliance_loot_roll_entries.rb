# frozen_string_literal: true

class CreateAllianceLootRollEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_loot_roll_entries do |t|
      t.bigint  :alliance_loot_roll_id, null: false
      t.bigint  :user_id,               null: false
      t.integer :roll_value
      t.string  :display_name
      t.boolean :is_reroll,             null: false, default: false

      t.timestamps
    end

    add_index :alliance_loot_roll_entries, :alliance_loot_roll_id
    add_index :alliance_loot_roll_entries, :user_id
    add_index :alliance_loot_roll_entries, [ :alliance_loot_roll_id, :user_id ], unique: true, name: "index_alliance_loot_roll_entries_on_roll_and_user"
    add_foreign_key :alliance_loot_roll_entries, :alliance_loot_rolls
    add_foreign_key :alliance_loot_roll_entries, :users
  end
end
