class AddSquadLeaderAndLocationToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :squad_leader, :string, if_not_exists: true
    add_column :events, :location, :string, if_not_exists: true
  end
end
