class AddPermissionSettingsToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :permission_role_1_id, :string, if_not_exists: true
    add_column :guilds, :permission_role_2_id, :string, if_not_exists: true
    add_column :guilds, :role_1_can_manage_roles, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_1_can_manage_applications, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_1_can_manage_guild_settings, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_2_can_manage_roles, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_2_can_manage_applications, :boolean, default: false, if_not_exists: true
    add_column :guilds, :role_2_can_manage_guild_settings, :boolean, default: false, if_not_exists: true
  end
end
