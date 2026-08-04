class UpdateDiscordEventSignupsUniquenessConstraint < ActiveRecord::Migration[8.0]
  def up
    # CRITICAL: Remove duplicates BEFORE creating unique index
    # Keep the first signup (by ID) for each user/event combination
    # Update it to use the first role found (or we could merge, but simpler to keep first)
    execute <<-SQL
      DELETE FROM discord_event_signups
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM discord_event_signups
        GROUP BY discord_event_id, discord_user_id
      )
    SQL
    
    # Remove old index that included role
    remove_index :discord_event_signups, name: 'index_discord_event_signups_unique', if_exists: true
    
    # Add new unique index for one signup per user per event (not per role)
    add_index :discord_event_signups, [:discord_event_id, :discord_user_id],
              unique: true,
              name: 'index_discord_event_signups_unique_user_event',
              if_not_exists: true
  end

  def down
    # Restore old index
    remove_index :discord_event_signups, name: 'index_discord_event_signups_unique_user_event', if_exists: true
    
    add_index :discord_event_signups, [:discord_event_id, :discord_user_id, :role],
              unique: true,
              name: 'index_discord_event_signups_unique',
              if_not_exists: true
  end
end
