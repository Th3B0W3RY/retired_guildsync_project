class CreateGuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :guilds, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.string :avatar_url
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.jsonb :settings, default: {}

      t.timestamps
    end

    add_index :guilds, :name, if_not_exists: true
  end
end
