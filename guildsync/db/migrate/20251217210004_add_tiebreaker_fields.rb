class AddTiebreakerFields < ActiveRecord::Migration[8.0]
  def change
    # Track which tiebreaker round an entry's roll is for
    add_column :loot_roll_entries, :tiebreaker_round, :integer, default: 0, null: false, if_not_exists: true
    
    # Track the current tiebreaker round for the loot roll
    add_column :loot_rolls, :current_tiebreaker_round, :integer, default: 0, null: false, if_not_exists: true
    
    # Store the tied user IDs when a tie is detected
    add_column :loot_rolls, :tied_discord_user_ids, :json, if_not_exists: true
  end
end
