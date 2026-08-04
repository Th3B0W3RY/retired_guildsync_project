module AdminAuditLogging
  extend ActiveSupport::Concern

  private

  def log_admin_action(action:, record: nil, changes_data: nil)
    admin_email = if respond_to?(:current_admin_email)
                    current_admin_email
                  else
                    session[:admin_email] || ENV["ADMIN_EMAIL"] || "unknown"
                  end
    AdminAuditLog.log_action(
      admin_email: admin_email,
      action: action,
      controller: controller_name,
      record: record,
      changes_data: changes_data,
      request: request
    )
  rescue => e
    Rails.logger.warn("Admin audit log failed for #{action}: #{e.class} #{e.message}")
  end
end

