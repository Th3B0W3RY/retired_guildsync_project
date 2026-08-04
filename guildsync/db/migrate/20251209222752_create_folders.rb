class CreateFolders < ActiveRecord::Migration[8.0]
  def change
    create_table :folders, if_not_exists: true do |t|
      t.string :name, null: false
      t.references :guild, null: false, foreign_key: true
      t.references :parent_folder, null: true, foreign_key: { to_table: :folders }

      t.timestamps
    end
  end
end
