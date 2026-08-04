# frozen_string_literal: true

# Logs member page views inside the /alliances/:id web hub (HTML GET 200 only).
module AllianceActivityViewLogging
  extend ActiveSupport::Concern

  included do
    after_action :log_alliance_hub_page_view
  end

  private

  def log_alliance_hub_page_view
    return unless request.get? || request.head?
    return unless response.status == 200
    return unless request.format.html?
    return unless user_signed_in? && current_user.present?
    return unless @alliance.present? && @alliance.persisted?

    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: nil,
      view_action: true,
      action_type: "alliance_page_view",
      description: %(Viewed #{controller_path}##{action_name}),
      page: "#{controller_path}##{action_name}"
    )
  end
end
