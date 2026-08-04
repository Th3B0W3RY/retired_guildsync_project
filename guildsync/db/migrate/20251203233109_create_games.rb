class CreateGames < ActiveRecord::Migration[8.0]
  def change
    create_table :games, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.jsonb :ocr_config, default: {}, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    
    add_index :games, :slug, unique: true, if_not_exists: true
    add_index :games, :name, unique: true, if_not_exists: true
  end
end
