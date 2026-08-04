class CreateGuildDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_documents, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :visibility, null: false, default: 0
      t.jsonb :content, default: {}
      t.string :slug, null: false

      t.timestamps
    end
    
    add_index :guild_documents, :slug, unique: true, if_not_exists: true
    add_index :guild_documents, [:guild_id, :visibility], if_not_exists: true
  end
end
