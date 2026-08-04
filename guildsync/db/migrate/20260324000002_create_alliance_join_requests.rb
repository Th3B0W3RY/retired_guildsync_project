# frozen_string_literal: true

class CreateAllianceJoinRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_join_requests do |t|
      t.references :alliance, null: false, foreign_key: true
      t.references :requesting_guild, null: false, foreign_key: { to_table: :guilds }
      t.references :requested_by_user, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :alliance_join_requests, [ :alliance_id, :requesting_guild_id ],
              unique: true,
              where: "status = 0",
              name: "index_alliance_join_requests_pending_unique"
  end
end
