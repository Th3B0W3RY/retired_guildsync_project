class AddPreferredLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :preferred_locale, :string, limit: 5, default: nil, if_not_exists: true
  end
end
