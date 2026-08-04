class AddDiscordScheduledEventIdToAllianceEventDiscordMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :alliance_event_discord_messages, :discord_scheduled_event_id, :string
  end
end
