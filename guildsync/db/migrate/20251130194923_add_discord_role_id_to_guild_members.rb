class AddDiscordRoleIdToGuildMembers < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_members, :discord_role_id, :string, if_not_exists: true
  end
end
