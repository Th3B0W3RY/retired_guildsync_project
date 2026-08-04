# frozen_string_literal: true

class AddDeletedAtToRecoverableUserContent < ActiveRecord::Migration[8.0]
  TABLES = %i[
    events
    discord_events
    polls
    loot_rolls
    guild_documents
    folders
    file_entries
    alliance_events
    alliance_polls
    alliance_loot_rolls
  ].freeze

  def change
    TABLES.each do |table_name|
      add_column table_name, :deleted_at, :datetime
      add_index table_name, :deleted_at
    end
  end
end
