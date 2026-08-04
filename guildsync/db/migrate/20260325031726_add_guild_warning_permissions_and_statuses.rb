class AddGuildWarningPermissionsAndStatuses < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :role_1_can_manage_warnings, :boolean, default: false, null: false
    add_column :guilds, :role_2_can_manage_warnings, :boolean, default: false, null: false
    add_column :guilds, :role_3_can_manage_warnings, :boolean, default: false, null: false
    add_column :guilds, :role_4_can_manage_warnings, :boolean, default: false, null: false

    create_table :guild_member_warning_statuses do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :warned_by, foreign_key: { to_table: :users }
      t.integer :warning_count, null: false, default: 0
      t.integer :state, null: false, default: 0
      t.text :last_warning_reason
      t.datetime :last_warned_at

      t.timestamps
    end

    add_index :guild_member_warning_statuses, [ :guild_id, :user_id ], unique: true, name: "idx_guild_member_warning_statuses_guild_user"
  end
end
