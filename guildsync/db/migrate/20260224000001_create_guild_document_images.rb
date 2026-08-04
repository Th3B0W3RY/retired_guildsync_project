# frozen_string_literal: true

class CreateGuildDocumentImages < ActiveRecord::Migration[8.0]
  def change
    create_table :guild_document_images, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
