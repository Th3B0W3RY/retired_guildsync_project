class AddKickMembersPermissionToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :role_1_can_kick_members, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_2_can_kick_members, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_3_can_kick_members, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_4_can_kick_members, :boolean, default: false, if_not_exists: true
  end
end
