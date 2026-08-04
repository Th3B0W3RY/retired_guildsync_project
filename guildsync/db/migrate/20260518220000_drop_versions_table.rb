# frozen_string_literal: true

class DropVersionsTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :versions, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
