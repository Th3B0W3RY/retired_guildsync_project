class CreateFileEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :file_entries, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :content_type
      t.integer :size
      t.boolean :compressed, default: false
      t.references :guild, null: false, foreign_key: true
      t.references :folder, null: true, foreign_key: true
      t.integer :uploaded_by, null: false

      t.timestamps
    end

    add_index :file_entries, :uploaded_by, if_not_exists: true
  end
end
