# frozen_string_literal: true

class CreateAllianceGuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_guilds do |t|
      t.bigint  :alliance_id,        null: false
      t.bigint  :guild_id,           null: false
      t.integer :status,             null: false, default: 0  # 0=active, 1=pending_invite, 2=left, 3=kicked
      t.bigint  :invited_by_user_id
      t.datetime :joined_at

      t.timestamps
    end

    add_index :alliance_guilds, :alliance_id
    add_index :alliance_guilds, :guild_id
    add_index :alliance_guilds, [ :alliance_id, :guild_id ], unique: true
    add_index :alliance_guilds, :guild_id, unique: true, where: "status = 0", name: "index_alliance_guilds_on_guild_id_active_unique"
    add_foreign_key :alliance_guilds, :alliances
    add_foreign_key :alliance_guilds, :guilds
    add_foreign_key :alliance_guilds, :users, column: :invited_by_user_id
  end
end
