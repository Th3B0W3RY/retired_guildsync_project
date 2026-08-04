# frozen_string_literal: true

class GuildWarningsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_warning_access, except: [ :my_status ]
  before_action :require_guild_member_for_my_warnings, only: [ :my_status ]

  def index
    @members = @guild.guild_members.includes(:user).where(status: :active)
    @warnable_members = @members.reject { |member| protected_warning_target?(member.user) }
    @warning_statuses_by_user_id = @guild.guild_member_warning_statuses.index_by(&:user_id)
    @no_warning_members, @warned_members, @banned_members = grouped_members
  end

  def create
    member = @guild.guild_members.includes(:user).find_by(user_id: params[:user_id], status: :active)
    if member.blank?
      return redirect_to(guild_warnings_path(@guild), alert: t("guild_warnings.alerts.member_not_found"))
    end
    if protected_warning_target?(member.user)
      return redirect_to(guild_warnings_path(@guild), alert: t("guild_warnings.alerts.protected_member"))
    end

    reason = sanitize_text_input(params[:reason]).to_s
    if reason.blank?
      return redirect_to(guild_warnings_path(@guild), alert: t("guild_warnings.alerts.reason_required"))
    end

    status = @guild.guild_member_warning_statuses.find_or_initialize_by(user_id: member.user_id)
    status.apply_warning!(reason: reason, issuer: current_user)
    GuildActivityLogger.log(
      guild: @guild,
      user: current_user,
      action_type: "member_warned",
      description: "Warned #{member.user.display_name}",
      target_name: member.user.display_name
    )

    GuildWarningDiscordDmJob.perform_later(@guild.id, member.user_id, reason, status.warning_count)

    redirect_to guild_warnings_path(@guild), notice: t("guild_warnings.alerts.warning_sent", user: member.user.display_name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to guild_warnings_path(@guild), alert: t("guild_warnings.alerts.warning_failed", error: e.message)
  end

  def update_lists
    states = params[:warning_states].is_a?(ActionController::Parameters) ? params[:warning_states].to_unsafe_h : {}

    ActiveRecord::Base.transaction do
      states.each do |user_id, target_state|
        member = @guild.guild_members.find_by(user_id: user_id, status: :active)
        next unless member
        next if protected_warning_target?(member.user)

        status = @guild.guild_member_warning_statuses.find_or_initialize_by(user_id: member.user_id)
        status.move_to_state!(target_state, issuer: current_user)
      end
    end

    GuildActivityLogger.log(
      guild: @guild,
      user: current_user,
      action_type: "warning_lists_updated",
      description: "Updated guild warning lists"
    )

    redirect_to guild_warnings_path(@guild), notice: t("guild_warnings.alerts.lists_updated")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to guild_warnings_path(@guild), alert: t("guild_warnings.alerts.list_update_failed", error: e.message)
  end

  private

  def set_guild
    @guild = current_user.guilds.find_by(id: params[:guild_id]) ||
             current_user.owned_guilds.find_by(id: params[:guild_id]) ||
             Guild.find_by(id: params[:guild_id], owner_id: current_user.id)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied") unless @guild
  end

  def require_warning_access
    unless current_user.plan_allows?(:warnings)
      redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
      return
    end
    return if can_manage_warnings?(@guild)

    redirect_to guild_path(@guild), alert: t("guild_warnings.alerts.access_denied")
  end

  def require_guild_member_for_my_warnings
    return if @guild.owner_id == current_user.id
    return if @guild.guild_members.exists?(user_id: current_user.id, status: :active)

    redirect_to dashboard_path, alert: t("guild_warnings.my_status.access_denied")
  end

  def grouped_members
    no_warning = []
    warned = []
    banned = []

    @members.each do |member|
      next if protected_warning_target?(member.user)

      status = @warning_statuses_by_user_id[member.user_id]
      state = status&.state || "no_warnings"
      case state
      when "banned" then banned << member
      when "warned" then warned << member
      else no_warning << member
      end
    end

    [ no_warning, warned, banned ]
  end

  def protected_warning_target?(user)
    return true if user.id == @guild.owner_id

    can_manage_warnings?(@guild, user)
  end

end
