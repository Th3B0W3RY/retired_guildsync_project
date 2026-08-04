# frozen_string_literal: true

# Shared before_action helpers for routes under /alliances/:alliance_id/…
# Uses find_by and a single flash string so unknown ids and non-members are not distinguished.
module AllianceNestedAccess
  extend ActiveSupport::Concern

  private

  def set_alliance
    @alliance = Alliance.find_by(id: params[:alliance_id])
    unless @alliance
      redirect_to dashboard_path, alert: t("controllers.guilds.access_denied")
      return
    end
  end

  def require_alliance_member
    return if @alliance.alliance_members.where(user: current_user, status: :active).exists?

    redirect_to dashboard_path, alert: t("controllers.guilds.access_denied")
  end
end
