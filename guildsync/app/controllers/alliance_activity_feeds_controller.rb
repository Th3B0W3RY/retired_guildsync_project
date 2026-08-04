# frozen_string_literal: true

require "csv"

class AllianceActivityFeedsController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member
  before_action :require_alliance_guild_owner

  PER_PAGE = 25

  def index
    preserve_session
    scope = alliance_activity_logs_scope.recent_first
    @total_count = scope.count
    page = [ params[:page].to_i, 1 ].max
    @logs = scope.includes(:user, :guild).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @current_page = page
    @action_types = AllianceActivityLog.for_alliance(@alliance).distinct.pluck(:action_type).sort
  end

  def export
    preserve_session
    scope = alliance_activity_logs_scope.recent_first.includes(:user, :guild)
    csv_data = CSV.generate(headers: true) do |csv|
      csv << %w[time_utc guildsync_username discord_username discord_server_name action details metadata_json]
      scope.each do |log|
        csv << [
          log.created_at.utc.iso8601,
          log.user ? log.user.username.to_s : "",
          discord_username_for_export(log.user),
          discord_server_name_for_export(log),
          log.action_type.to_s,
          log.description.to_s,
          log.metadata.present? ? log.metadata.to_json : ""
        ]
      end
    end
    filename = "alliance-#{@alliance.id}-activity-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.csv"
    send_data csv_data, filename: filename, type: "text/csv", disposition: "attachment"
  end

  def export_json
    preserve_session
    scope = alliance_activity_logs_scope.recent_first.includes(:user, :guild)
    rows = scope.map do |log|
      {
        id: log.id,
        created_at_utc: log.created_at.utc.iso8601,
        guildsync_username: log.user ? log.user.username.to_s : "",
        discord_username: discord_username_for_export(log.user),
        discord_server_name: discord_server_name_for_export(log),
        action: log.action_type.to_s,
        details: log.description.to_s,
        metadata: log.metadata
      }
    end
    render json: { alliance_id: @alliance.id, rows: rows }
  end

  private

  def preserve_session
    return unless user_signed_in? && current_user.present?

    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def require_alliance_guild_owner
    return if alliance_owner_in_active_guild?(@alliance)

    redirect_to alliance_path(@alliance), alert: t("alliance_activity_feed.access_denied")
  end

  def alliance_activity_logs_scope
    scope = AllianceActivityLog.for_alliance(@alliance)
    scope = scope.where(action_type: params[:action_type]) if params[:action_type].present?
    if params[:q].present?
      q = params[:q].to_s.strip
      safe = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope = scope.where("description ILIKE :q OR metadata::text ILIKE :q", q: safe)
    end
    scope
  end

  def discord_username_for_export(user)
    return "" unless user
    user.discord_username.presence || user.discord_global_name.to_s.presence || ""
  end

  def discord_server_name_for_export(log)
    (log.metadata || {})["discord_server_name"].presence ||
      log.guild&.name.to_s.presence ||
      ""
  end
end
