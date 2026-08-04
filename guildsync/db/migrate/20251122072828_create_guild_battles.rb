class CreateGuildBattles < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_battles, if_not_exists: true do |t|
      t.references :challenger_guild, null: false, foreign_key: { to_table: :guilds }
      t.references :defender_guild, null: false, foreign_key: { to_table: :guilds }
      t.references :challenger_owner, null: false, foreign_key: { to_table: :users }
      t.references :defender_owner, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0
      t.datetime :scheduled_at
      t.string :location
      t.integer :max_participants
      t.text :notes
      t.string :discord_event_id_challenger
      t.string :discord_event_id_defender

      t.timestamps
    end
    # Indexes are automatically created by t.references above
  end
end
