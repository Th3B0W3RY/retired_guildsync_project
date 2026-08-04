# frozen_string_literal: true

class AddAlliancePermissionToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :role_1_can_manage_alliance, :boolean, null: false, default: false
    add_column :guilds, :role_2_can_manage_alliance, :boolean, null: false, default: false
    add_column :guilds, :role_3_can_manage_alliance, :boolean, null: false, default: false
    add_column :guilds, :role_4_can_manage_alliance, :boolean, null: false, default: false
  end
end
