class AddMemberTagsAndSplitAlliancePermissions < ActiveRecord::Migration[8.0]
  def up
    (1..4).each do |slot|
      add_column :guilds, :"role_#{slot}_can_invite_alliance_guilds", :boolean, default: false, null: false
      add_column :guilds, :"role_#{slot}_can_kick_alliance_guilds", :boolean, default: false, null: false
      add_column :guilds, :"role_#{slot}_can_manage_tags", :boolean, default: false, null: false
    end

    create_table :guild_tags do |t|
      t.references :guild, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6366f1"
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :guild_tags, [ :guild_id, :name ], unique: true

    create_table :guild_member_tags do |t|
      t.references :guild_member, null: false, foreign_key: true
      t.references :guild_tag, null: false, foreign_key: true
      t.references :assigned_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :guild_member_tags, [ :guild_member_id, :guild_tag_id ], unique: true

    create_table :alliance_tags do |t|
      t.references :alliance, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6366f1"
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :alliance_tags, [ :alliance_id, :name ], unique: true

    create_table :alliance_member_tags do |t|
      t.references :alliance_member, null: false, foreign_key: true
      t.references :alliance_tag, null: false, foreign_key: true
      t.references :assigned_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :alliance_member_tags, [ :alliance_member_id, :alliance_tag_id ], unique: true

    # Backfill new split permissions from previous alliance manager flag.
    execute <<~SQL
      UPDATE guilds
      SET
        role_1_can_invite_alliance_guilds = role_1_can_manage_alliance,
        role_1_can_kick_alliance_guilds = role_1_can_manage_alliance,
        role_2_can_invite_alliance_guilds = role_2_can_manage_alliance,
        role_2_can_kick_alliance_guilds = role_2_can_manage_alliance,
        role_3_can_invite_alliance_guilds = role_3_can_manage_alliance,
        role_3_can_kick_alliance_guilds = role_3_can_manage_alliance,
        role_4_can_invite_alliance_guilds = role_4_can_manage_alliance,
        role_4_can_kick_alliance_guilds = role_4_can_manage_alliance
    SQL
  end

  def down
    drop_table :alliance_member_tags
    drop_table :alliance_tags
    drop_table :guild_member_tags
    drop_table :guild_tags

    (1..4).each do |slot|
      remove_column :guilds, :"role_#{slot}_can_manage_tags"
      remove_column :guilds, :"role_#{slot}_can_kick_alliance_guilds"
      remove_column :guilds, :"role_#{slot}_can_invite_alliance_guilds"
    end
  end
end
