class AddReceiverToGuildBattleMessages < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:guild_battle_messages, :receiver_id)
    add_reference :guild_battle_messages, :receiver, null: true, foreign_key: { to_table: :users }
  end
end

