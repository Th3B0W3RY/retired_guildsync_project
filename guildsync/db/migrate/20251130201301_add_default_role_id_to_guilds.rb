class AddDefaultRoleIdToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :default_role_id, :string, if_not_exists: true
  end
end
