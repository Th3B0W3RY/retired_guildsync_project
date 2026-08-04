class AddDiscordRoleMentionsToDiscordEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :discord_events, :discord_role_mentions, :json, if_not_exists: true
  end
end
