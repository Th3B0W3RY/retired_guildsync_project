# frozen_string_literal: true

require "csv"

class ActivityFeedController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_activity_feed_access

  PER_PAGE = 25

  def export
    preserve_session
    scope = guild_activity_logs_scope.recent_first.includes(:user)
    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "time_utc",
        "guildsync_username",
        "action",
        "details",
        "metadata_json"
      ]
      scope.each do |log|
        csv << [
          log.created_at.utc.iso8601,
          log.user ? (log.user.username.presence || log.user.email).to_s : "",
          helpers.format_activity_action_type(log.action_type),
          log.description.to_s,
          log.metadata.present? ? log.metadata.to_json : ""
        ]
      end
    end
    filename = "guild-#{@guild.id}-activity-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.csv"
    send_data csv_data, filename: filename, type: "text/csv", disposition: "attachment"
  end

  def index
    preserve_session
    scope = guild_activity_logs_scope.recent_first
    @total_count = scope.count
    page = [ params[:page].to_i, 1 ].max
    @logs = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @current_page = page
    @action_types = GuildActivityLog.for_guild(@guild).distinct.pluck(:action_type).sort
    @members_for_filter = @guild.members.distinct.order(:username).select(:id, :username, :email)
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def set_guild
    gid = params[:id]
    @guild = current_user.guilds.find_by(id: gid)
    @guild ||= current_user.owned_guilds.find_by(id: gid)
    @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)
    return if @guild

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end

  def require_activity_feed_access
    unless current_user.plan_allows?(:activity_feed)
      redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
      return
    end
    return if can_view_activity_feed?(@guild)

    redirect_to guild_path(@guild), alert: t("activity_feed.access_denied")
  end

  def guild_activity_logs_scope
    scope = GuildActivityLog.for_guild(@guild)
    scope = scope.where(action_type: params[:action_type]) if params[:action_type].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    if params[:q].present?
      q = params[:q].to_s.strip
      safe = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope = scope.where("description ILIKE :q OR metadata::text ILIKE :q", q: safe)
    end
    scope
  end
end
