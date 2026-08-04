class CreateDiscordRoleSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_role_syncs, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.string :role_id, null: false
      t.string :role_name, null: false

      t.timestamps
    end

    add_index :discord_role_syncs, [:guild_id, :role_id], unique: true, if_not_exists: true
  end
end
