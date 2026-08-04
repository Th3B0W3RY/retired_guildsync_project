class AddDiscordDisplayNameToDiscordEventSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_event_signups, :discord_display_name, :string, if_not_exists: true
  end
end
