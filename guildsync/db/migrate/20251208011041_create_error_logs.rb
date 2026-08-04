class CreateErrorLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :error_logs, if_not_exists: true do |t|
      t.string :error_class, null: false
      t.text :message, null: false
      t.text :backtrace
      t.jsonb :context
      t.datetime :occurred_at, null: false
      t.datetime :resolved_at
      t.string :resolved_by

      t.timestamps
    end

    add_index :error_logs, :occurred_at, if_not_exists: true
    add_index :error_logs, :resolved_at, if_not_exists: true
  end
end
