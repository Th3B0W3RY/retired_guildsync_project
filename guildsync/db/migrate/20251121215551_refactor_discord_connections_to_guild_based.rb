class RefactorDiscordConnectionsToGuildBased < ActiveRecord::Migration[8.0]
  def up
    # Remove old unique indexes
    remove_index :discord_connections, :user_id if index_exists?(:discord_connections, :user_id)
    remove_index :discord_connections, :discord_user_id if index_exists?(:discord_connections, :discord_user_id)
    
    # Delete all existing discord_connections since they're user-based and we're moving to guild-based
    # Users will need to reconnect their Discord accounts per guild
    execute "DELETE FROM discord_connections"
    
    # Add guild_id column (nullable initially for safety, but we'll make it required)
    unless column_exists?(:discord_connections, :guild_id)
      add_reference :discord_connections, :guild, null: false, foreign_key: true, index: false
    end
    
    # Add new unique index on guild_id (one connection per guild)
    add_index :discord_connections, :guild_id, unique: true, if_not_exists: true
    
    # Remove the unique constraint on discord_user_id (users can connect same Discord account to multiple guilds)
    # But keep an index for lookups
    add_index :discord_connections, :discord_user_id, if_not_exists: true
    
    # user_id should still be present (the owner), but not unique
    # It's already a foreign key, so we just need to ensure it's indexed for lookups
    add_index :discord_connections, :user_id, if_not_exists: true
  end

  def down
    # Remove new indexes
    remove_index :discord_connections, :guild_id if index_exists?(:discord_connections, :guild_id)
    remove_index :discord_connections, :user_id if index_exists?(:discord_connections, :user_id)
    remove_index :discord_connections, :discord_user_id if index_exists?(:discord_connections, :discord_user_id)
    
    # Remove guild_id
    remove_reference :discord_connections, :guild, foreign_key: true
    
    # Restore old unique indexes
    add_index :discord_connections, :user_id, unique: true, if_not_exists: true
    add_index :discord_connections, :discord_user_id, unique: true, if_not_exists: true
  end
end
