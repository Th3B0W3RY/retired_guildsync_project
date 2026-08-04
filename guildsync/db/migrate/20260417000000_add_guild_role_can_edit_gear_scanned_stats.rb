# frozen_string_literal: true

class AddGuildRoleCanEditGearScannedStats < ActiveRecord::Migration[8.0]
  def change
    (1..4).each do |slot|
      add_column :guilds, :"role_#{slot}_can_edit_gear_scanned_stats", :boolean, default: false, null: false
    end
  end
end
