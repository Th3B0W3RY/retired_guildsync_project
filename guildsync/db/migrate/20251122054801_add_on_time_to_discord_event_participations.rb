class AddOnTimeToDiscordEventParticipations < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_event_participations, :on_time, :boolean, default: false, null: false, if_not_exists: true
  end
end
