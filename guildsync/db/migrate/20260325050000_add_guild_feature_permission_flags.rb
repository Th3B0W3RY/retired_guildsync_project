class AddGuildFeaturePermissionFlags < ActiveRecord::Migration[8.0]
  def change
    (1..4).each do |slot|
      add_column :guilds, :"role_#{slot}_can_manage_events", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_manage_polls", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_manage_loot_rolls", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_manage_discord_channels", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_view_activity_feed", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_export_members_csv", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_use_message_center", :boolean, default: false, null: false, if_not_exists: true
      add_column :guilds, :"role_#{slot}_can_manage_gear_requests", :boolean, default: false, null: false, if_not_exists: true
    end
  end
end
