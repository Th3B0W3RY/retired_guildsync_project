class AddDismissedToGuildInvites < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_invites, :dismissed, :boolean, default: false, null: false, if_not_exists: true
  end
end
