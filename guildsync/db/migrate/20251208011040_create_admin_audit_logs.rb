class CreateAdminAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_audit_logs, if_not_exists: true do |t|
      t.string :admin_email, null: false
      t.string :action, null: false
      t.string :controller, null: false
      t.string :record_type
      t.bigint :record_id
      t.text :changes_data
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :admin_audit_logs, :admin_email, if_not_exists: true
    add_index :admin_audit_logs, [:record_type, :record_id], if_not_exists: true
    add_index :admin_audit_logs, :created_at, if_not_exists: true
  end
end

