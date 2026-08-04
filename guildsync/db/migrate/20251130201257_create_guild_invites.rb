class CreateGuildInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_invites, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.integer :status, default: 0
      t.references :invited_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
    
    add_index :guild_invites, [:user_id, :guild_id], unique: true, if_not_exists: true
  end
end
