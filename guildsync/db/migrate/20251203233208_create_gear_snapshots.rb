class CreateGearSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :gear_snapshots, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.string :source, null: false
      t.text :raw_text
      t.jsonb :data, default: {}, null: false
      t.text :embedding
      t.boolean :validation_passed, default: true
      t.text :validation_warning
      t.timestamps
    end

    add_index :gear_snapshots, [:guild_id, :user_id], if_not_exists: true
    add_index :gear_snapshots, [:guild_id, :user_id, :created_at], name: 'index_gear_snapshots_latest', if_not_exists: true
    add_index :gear_snapshots, [:game_id, :created_at], if_not_exists: true
    add_index :gear_snapshots, :data, using: :gin, if_not_exists: true
    add_index :gear_snapshots, :created_at, if_not_exists: true
  end
end
