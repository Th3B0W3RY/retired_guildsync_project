class AddIgdbFieldsToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :igdb_id, :bigint, if_not_exists: true
    add_column :games, :igdb_synced_at, :datetime, if_not_exists: true
    add_column :games, :igdb_data, :jsonb, default: {}, null: false, if_not_exists: true
    add_column :games, :guild_oriented, :boolean, default: false, null: false, if_not_exists: true
    add_column :games, :verified_by_igdb, :boolean, default: false, null: false, if_not_exists: true
    
    # Add index for efficient querying
    add_index :games, :igdb_id, unique: true, where: 'igdb_id IS NOT NULL', if_not_exists: true
    add_index :games, :guild_oriented, if_not_exists: true
    add_index :games, :verified_by_igdb, if_not_exists: true
  end
end
