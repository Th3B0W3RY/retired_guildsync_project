class AddDiscordRoleMentionsToPolls < ActiveRecord::Migration[8.0]
  def change
    add_column :polls, :discord_role_mentions, :json, if_not_exists: true
  end
end

