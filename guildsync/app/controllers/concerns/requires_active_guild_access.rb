# frozen_string_literal: true

module RequiresActiveGuildAccess
  extend ActiveSupport::Concern

  private

  def require_active_guild_access
    return unless defined?(@guild) && @guild.present?
    return unless @guild.respond_to?(:archived?) && @guild.archived?

    redirect_to guild_archives_path, alert: t("guild_archives.alerts.archived_unavailable")
  end
end
