# frozen_string_literal: true

class CreateAlliances < ActiveRecord::Migration[8.0]
  def change
    create_table :alliances do |t|
      t.string  :name,            null: false
      t.text    :description
      t.integer :status,          null: false, default: 0  # 0=active, 1=disbanded
      t.bigint  :leader_guild_id, null: false
      t.bigint  :leader_user_id,  null: false

      t.timestamps
    end

    add_index :alliances, :leader_guild_id
    add_index :alliances, :leader_user_id
    add_index :alliances, :status
    add_foreign_key :alliances, :guilds, column: :leader_guild_id
    add_foreign_key :alliances, :users,  column: :leader_user_id
  end
end
