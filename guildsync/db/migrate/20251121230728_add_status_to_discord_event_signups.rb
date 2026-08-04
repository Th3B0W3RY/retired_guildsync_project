class AddStatusToDiscordEventSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_event_signups, :status, :integer, default: 0, null: false, if_not_exists: true
  end
end
