class CreateGuildDocumentFolders < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_document_folders, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, default: '#3b82f6'
      t.integer :position, default: 0

      t.timestamps
    end
  end
end
