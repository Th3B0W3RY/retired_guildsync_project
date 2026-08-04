class AddInitiatedByToOcrRequests < ActiveRecord::Migration[8.0]
  def change
    add_reference :ocr_requests, :initiated_by, null: true, foreign_key: { to_table: :users }
  end
end
