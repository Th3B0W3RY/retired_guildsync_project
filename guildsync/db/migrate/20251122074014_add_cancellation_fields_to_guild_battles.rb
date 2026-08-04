class AddCancellationFieldsToGuildBattles < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_battles, :cancellation_requested_by_challenger, :boolean, default: false, null: false, if_not_exists: true
    add_column :guild_battles, :cancellation_requested_by_defender, :boolean, default: false, null: false, if_not_exists: true
  end
end
