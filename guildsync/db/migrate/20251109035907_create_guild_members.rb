class CreateGuildMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_members, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.datetime :joined_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :guild_members, [ :user_id, :guild_id ], unique: true, if_not_exists: true
  end
end
