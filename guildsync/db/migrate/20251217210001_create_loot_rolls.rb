class CreateLootRolls < ActiveRecord::Migration[8.0]
  def change
    create_table :loot_rolls, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.integer :min_roll, default: 1, null: false
      t.integer :max_roll, default: 100, null: false
      t.boolean :anonymous, default: false, null: false
      t.datetime :deadline_at
      t.integer :status, default: 0, null: false
      t.string :discord_channel_id
      t.string :discord_message_id
      t.json :allowed_role_ids
      t.bigint :winner_entry_id

      t.timestamps
    end

    add_index :loot_rolls, :status, if_not_exists: true
    add_index :loot_rolls, :deadline_at, if_not_exists: true
  end
end
