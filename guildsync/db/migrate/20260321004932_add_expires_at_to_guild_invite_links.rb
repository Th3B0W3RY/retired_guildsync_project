class AddExpiresAtToGuildInviteLinks < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_invite_links, :expires_at, :datetime
  end
end
