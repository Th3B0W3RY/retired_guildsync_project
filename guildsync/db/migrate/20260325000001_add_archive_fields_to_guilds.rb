class AddArchiveFieldsToGuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :guilds, :archived_at, :datetime
    add_column :guilds, :scheduled_purge_at, :datetime

    add_index :guilds, :archived_at
    add_index :guilds, :scheduled_purge_at
  end
end
