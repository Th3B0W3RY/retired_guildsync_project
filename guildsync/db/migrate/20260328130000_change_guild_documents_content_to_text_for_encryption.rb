# frozen_string_literal: true

class ChangeGuildDocumentsContentToTextForEncryption < ActiveRecord::Migration[8.0]
  def up
    change_column :guild_documents, :content, :text, using: "(content)::text", default: "{}", null: false
  end

  def down
    change_column :guild_documents, :content, :jsonb, using: "content::jsonb", default: {}, null: false
  end
end
