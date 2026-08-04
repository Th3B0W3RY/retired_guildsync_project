# frozen_string_literal: true

# PaperTrail is still enabled on ApplicationRecord; the versions table must exist.
# Recreates the table if missing (e.g. after a partial schema sync).
class RecreateVersionsForPaperTrail < ActiveRecord::Migration[8.0]
  def change
    return if table_exists?(:versions)

    create_table :versions do |t|
      t.string :item_type, null: false
      t.bigint :item_id, null: false
      t.string :event, null: false
      t.string :whodunnit
      t.text :object
      t.text :object_changes
      t.datetime :created_at
    end

    add_index :versions, %i[item_type item_id]
  end
end
