class AddRole3AndRole4PermissionSettingsToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :permission_role_3_id, :string, if_not_exists: true
    add_column :guilds, :permission_role_4_id, :string, if_not_exists: true
    add_column :guilds, :role_3_can_manage_roles, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_3_can_manage_applications, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_3_can_manage_guild_settings, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_4_can_manage_roles, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_4_can_manage_applications, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_4_can_manage_guild_settings, :boolean, default: false, if_not_exists: true
  end
end
