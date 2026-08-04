# frozen_string_literal: true

class MegaSystemsPlanColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :beta_features_enabled, :boolean, default: false, null: false
    add_column :users, :alliance_downgrade_snapshot, :jsonb, default: {}, null: false

    add_column :guilds, :discord_invite_url, :string

    add_column :error_logs, :severity, :string, default: "medium", null: false
    add_column :error_logs, :cause, :text

    add_column :alliances, :chat_discord_channel_id, :string

    add_index :error_logs, :severity
  end
end
