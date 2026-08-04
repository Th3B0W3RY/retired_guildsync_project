class AddArchivedToUsers < ActiveRecord::Migration[8.0]
    def change
      add_column :users, :archived, :boolean, default: false, null: false, if_not_exists: true
      add_index :users, :archived, if_not_exists: true
    end
  end