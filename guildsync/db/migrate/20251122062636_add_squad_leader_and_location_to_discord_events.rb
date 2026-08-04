class AddSquadLeaderAndLocationToDiscordEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_events, :squad_leader, :string, if_not_exists: true
    add_column :discord_events, :location, :string, if_not_exists: true
  end
end
