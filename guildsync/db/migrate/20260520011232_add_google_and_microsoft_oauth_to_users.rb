class AddGoogleAndMicrosoftOAuthToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :google_uid, :string
    add_column :users, :microsoft_uid, :string

    add_index :users, :google_uid, unique: true, where: "(google_uid IS NOT NULL)"
    add_index :users, :microsoft_uid, unique: true, where: "(microsoft_uid IS NOT NULL)"
  end
end
