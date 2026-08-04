class AddDiscordFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :discord_event_id, :string, if_not_exists: true
    add_column :events, :discord_message_id, :string, if_not_exists: true
    add_index :events, :discord_event_id, if_not_exists: true
    add_index :events, :discord_message_id, if_not_exists: true
  end
end
