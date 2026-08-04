class CreateGuildGames < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_games, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.boolean :primary, default: false, null: false
      t.timestamps
    end

    add_index :guild_games, [:guild_id, :game_id], unique: true, if_not_exists: true
    # Note: guild_id and game_id indexes are automatically created by t.references
    # Quote "primary" since it's a PostgreSQL reserved keyword
    add_index :guild_games, [:guild_id, :primary], where: '"primary" = true', if_not_exists: true
  end
end
