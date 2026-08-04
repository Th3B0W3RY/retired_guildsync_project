class AdminAuditLog < ApplicationRecord

  validates :admin_email, :action, :controller, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_admin, ->(email) { where(admin_email: email) }
  scope :for_record, ->(type, id) { where(record_type: type, record_id: id) }

  def self.log_action(admin_email:, action:, controller:, record: nil, changes_data: nil, request: nil)
    create!(
      admin_email: admin_email,
      action: action,
      controller: controller,
      record_type: record&.class&.name,
      record_id: record&.id,
      changes_data: changes_data&.to_json,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  end
end

