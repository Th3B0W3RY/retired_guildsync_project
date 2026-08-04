# frozen_string_literal: true

class RenameProfanityUpdateLogsErrors < ActiveRecord::Migration[8.0]
  def change
    rename_column :profanity_update_logs, :errors, :error_messages
  end
end
