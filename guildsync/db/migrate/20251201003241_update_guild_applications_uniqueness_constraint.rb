class UpdateGuildApplicationsUniquenessConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing unique index that prevents all re-applications
    remove_index :guild_applications, name: 'index_guild_applications_on_user_and_guild'
    
    # Add a partial unique index that only enforces uniqueness for pending applications
    # This allows users to re-apply after rejection
    add_index :guild_applications, [:user_id, :guild_id],
              unique: true,
              where: "status = 0", # 0 is pending status
              name: 'index_guild_applications_on_user_and_guild_pending',
              if_not_exists: true
  end

  def down
    # Remove the partial unique index
    remove_index :guild_applications, name: 'index_guild_applications_on_user_and_guild_pending'
    
    # Restore the original unique index
    add_index :guild_applications, [:user_id, :guild_id],
              unique: true,
              name: 'index_guild_applications_on_user_and_guild',
              if_not_exists: true
  end
end
