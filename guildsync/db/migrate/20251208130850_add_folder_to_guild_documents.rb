class AddFolderToGuildDocuments < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:guild_documents, :folder_id)
    add_reference :guild_documents, :folder, null: true, foreign_key: { to_table: :guild_document_folders }, index: true
  end
end
