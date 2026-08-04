class FixGuildNameUniqueness < ActiveRecord::Migration[8.0]
  def change
    # Remove global uniqueness on name
    remove_index :guilds, :name if index_exists?(:guilds, :name)
    
    # Remove any PostgreSQL unique constraint that might exist
    execute "ALTER TABLE guilds DROP CONSTRAINT IF EXISTS guilds_name_key;"
    
    # Add correct uniqueness: name must be unique *per owner*
    add_index :guilds, [:owner_id, :name], unique: true, name: "index_guilds_on_owner_id_and_name", if_not_exists: true
  end
end
