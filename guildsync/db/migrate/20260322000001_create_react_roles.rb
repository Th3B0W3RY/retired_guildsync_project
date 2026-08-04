class CreateReactRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :react_roles do |t|
      t.references :guild, null: false, foreign_key: true
      t.integer :position, null: false           # 1, 2, or 3
      t.string :role_id, null: false             # Discord role snowflake
      t.string :role_name, null: false           # Display name (cached from DiscordRoleSync)
      t.string :emoji_name, null: false          # Unicode character OR custom emoji name
      t.string :emoji_id                         # Custom emoji snowflake; null for unicode emoji
      t.boolean :is_custom_emoji, default: false, null: false
      t.string :channel_id                       # Discord channel where the embed is posted
      t.string :message_id                       # Discord message ID of the deployed embed
      t.timestamps
    end

    add_index :react_roles, [ :guild_id, :position ], unique: true
    # Fast lookup in gateway reaction events: given a message_id, find all react_roles for that guild
    add_index :react_roles, [ :guild_id, :message_id ],
              name: "idx_react_roles_guild_message"
  end
end
