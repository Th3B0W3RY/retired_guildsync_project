class CreateGuildBattleMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_battle_messages, if_not_exists: true do |t|
      t.references :guild_battle, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :content

      t.timestamps
    end
  end
end
