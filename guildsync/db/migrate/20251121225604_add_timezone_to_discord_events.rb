class AddTimezoneToDiscordEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_events, :timezone, :string, null: false, default: "UTC", if_not_exists: true
  end
end
