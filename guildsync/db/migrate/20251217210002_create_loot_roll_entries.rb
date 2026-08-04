class CreateLootRollEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :loot_roll_entries, if_not_exists: true do |t|
      t.references :loot_roll, null: false, foreign_key: true
      t.string :discord_user_id, null: false
      t.string :display_name, null: false
      t.integer :roll_value, null: false
      t.integer :discord_role_position
      t.boolean :is_reroll, default: false, null: false

      t.timestamps
    end

    add_index :loot_roll_entries, [:loot_roll_id, :discord_user_id], unique: true, name: "index_loot_roll_entries_unique_user", if_not_exists: true
    add_index :loot_roll_entries, :roll_value, if_not_exists: true
  end
end
