class AddDeactivationFieldsToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :deactivated_at, :datetime, if_not_exists: true
    add_column :games, :deactivated_by_id, :integer, if_not_exists: true
    add_column :games, :deactivation_reason, :text, if_not_exists: true
    
    # Add foreign key for deactivated_by_id
    # Use on_delete: :nullify so games aren't deleted when the deactivating user is deleted
    unless foreign_key_exists?(:games, :users, column: :deactivated_by_id)
      add_foreign_key :games, :users, column: :deactivated_by_id, on_delete: :nullify
    end
    
    # Add index for efficient querying
    add_index :games, :deactivated_at, if_not_exists: true
    add_index :games, :deactivated_by_id, if_not_exists: true
  end
end
