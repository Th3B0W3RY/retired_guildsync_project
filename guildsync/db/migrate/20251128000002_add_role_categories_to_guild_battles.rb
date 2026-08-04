class AddRoleCategoriesToGuildBattles < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_battles, :role_categories, :jsonb, default: [], if_not_exists: true
  end
end

