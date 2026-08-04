class CreateErrorBatchReports < ActiveRecord::Migration[8.0]
  def change
    create_table :error_batch_reports do |t|
      t.datetime :period_start,    null: false
      t.datetime :period_end,      null: false
      t.integer  :total_errors,    null: false, default: 0
      t.integer  :unique_clusters, null: false, default: 0
      t.jsonb    :report_data,     null: false, default: {}
      t.datetime :delivered_at
      t.string   :triggered_by,    null: false, default: "scheduled"

      t.timestamps
    end

    add_index :error_batch_reports, :created_at
    add_index :error_batch_reports, :period_end
  end
end
