# frozen_string_literal: true

class IpMembershipAuditJob
  include Sidekiq::Worker

  def perform(user_id = nil)
    service = IpMembershipEnforcementService.new
    if user_id.present?
      user = User.find_by(id: user_id)
      service.audit_user!(user) if user
    else
      service.audit_all_recent!
    end
  rescue => e
    Rails.logger.error("[IpMembershipAuditJob] Failed: #{e.class}: #{e.message}")
  end
end
