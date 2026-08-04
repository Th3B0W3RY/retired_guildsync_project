class AddAcceptAndRejectMessagesToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :accept_message, :text, if_not_exists: true
    add_column :guilds, :reject_message, :text, if_not_exists: true
  end
end
