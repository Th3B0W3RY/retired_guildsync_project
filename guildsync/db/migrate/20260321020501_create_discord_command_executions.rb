class CreateDiscordCommandExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_command_executions do |t|
      t.string :interaction_token, null: false
      t.string :command_key, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at

      t.timestamps
    end
    add_index :discord_command_executions, [:interaction_token, :command_key], unique: true, name: "idx_discord_cmd_exec_idempotency"
  end
end
