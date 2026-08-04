# frozen_string_literal: true

class AllianceMembersController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member

  def index
    preserve_session
    @alliance_members = @alliance.alliance_members
                                 .where(status: :active)
                                 .includes(:user, :guild, :alliance_member_tags, alliance_tags: [])
                                 .order(:role, "users.username")
    @guilds_in_alliance = @alliance.alliance_guilds.where(status: :active).includes(:guild)
    @alliance_tags = @alliance.alliance_tags.order(:name)
    @can_manage_alliance_member_tags = can_manage_alliance_tags?(@alliance)

    respond_to do |format|
      format.html
      format.csv { send_data generate_alliance_members_csv(@alliance_members), filename: "alliance-#{@alliance.id}-members-#{Date.current}.csv", type: "text/csv" }
    end
  end

  # DELETE /alliances/:alliance_id/alliance_members/remove?user_id=X
  def remove
    preserve_session
    target = AllianceMember.find_by(alliance: @alliance, user_id: params[:user_id], status: :active)
    unless target
      redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.errors.not_found")
      return
    end

    unless can_kick_target?(target)
      alert_key = protected_alliance_target?(@alliance, target.user) &&
                  alliance_custom_manager_in_active_guild?(@alliance) &&
                  !alliance_owner_in_active_guild?(@alliance) ? "alliance_members.errors.protected_target" : "alliance_members.errors.unauthorized"
      redirect_to alliance_alliance_members_path(@alliance), alert: t(alert_key)
      return
    end

    target.update!(status: :removed)
    redirect_to alliance_alliance_members_path(@alliance), notice: t("alliance_members.removed")
  end

  # DELETE /alliances/:alliance_id/alliance_members/bulk_remove
  def bulk_remove
    preserve_session
    unless can_kick_alliance_actions?(@alliance)
      redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.errors.unauthorized")
      return
    end

    user_ids = (params[:user_ids] || []).map(&:to_i).compact
    targets = @alliance.alliance_members.where(user_id: user_ids, status: :active)
    targets = filter_kickable_targets(targets)

    AllianceMember.where(id: Array(targets).map(&:id)).update_all(status: AllianceMember.statuses[:removed])

    redirect_to alliance_alliance_members_path(@alliance), notice: t("alliance_members.bulk_removed")
  end

  def create_tag
    preserve_session
    unless @alliance.leader_user_id == current_user.id
      redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.errors.tags_owner_only")
      return
    end

    tag = @alliance.alliance_tags.build(name: params[:name].to_s.strip, color: params[:color].to_s.strip, created_by: current_user)
    if tag.save
      redirect_to alliance_alliance_members_path(@alliance), notice: t("alliance_members.tags.created")
    else
      redirect_to alliance_alliance_members_path(@alliance), alert: tag.errors.full_messages.to_sentence
    end
  end

  def assign_tag
    preserve_session
    unless can_manage_alliance_tags?(@alliance)
      redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.errors.unauthorized")
      return
    end

    member = @alliance.alliance_members.find(params[:member_id])
    tag = @alliance.alliance_tags.find(params[:tag_id])
    member.alliance_member_tags.find_or_create_by!(alliance_tag: tag) { |amt| amt.assigned_by = current_user }
    redirect_to alliance_alliance_members_path(@alliance), notice: t("alliance_members.tags.assigned")
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.tags.not_found")
  end

  def remove_tag
    preserve_session
    unless can_manage_alliance_tags?(@alliance)
      redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.errors.unauthorized")
      return
    end

    member = @alliance.alliance_members.find(params[:member_id])
    tag = @alliance.alliance_tags.find(params[:tag_id])
    member.alliance_member_tags.where(alliance_tag: tag).destroy_all
    redirect_to alliance_alliance_members_path(@alliance), notice: t("alliance_members.tags.removed")
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_members_path(@alliance), alert: t("alliance_members.tags.not_found")
  end

  private

  def can_kick_target?(target)
    return false unless can_kick_alliance_actions?(@alliance)
    return false if target.user == current_user

    if alliance_custom_kicker_in_active_guild?(@alliance) && !alliance_owner_in_active_guild?(@alliance)
      return false if protected_alliance_target?(@alliance, target.user)
      return false unless kickable_guild_ids_for_current_user.include?(target.guild_id)
    end

    true
  end

  def filter_kickable_targets(targets)
    if alliance_owner_in_active_guild?(@alliance)
      targets.where.not(user_id: current_user.id)
    else
      allowed_guild_ids = kickable_guild_ids_for_current_user
      Array(targets).select do |member|
        member.user_id != current_user.id &&
          !protected_alliance_target?(@alliance, member.user) &&
          allowed_guild_ids.include?(member.guild_id)
      end
    end
  end

  def kickable_guild_ids_for_current_user
    alliance_active_member_guilds(@alliance, current_user)
      .select { |guild| can_kick_alliance_guilds?(guild, current_user) }
      .map(&:id)
  end

  def can_manage_alliance_tags?(alliance)
    alliance_owner_in_active_guild?(alliance) ||
      alliance_active_member_guilds(alliance, current_user).any? { |guild| can_manage_tags?(guild, current_user) }
  end

  def generate_alliance_members_csv(alliance_members)
    CSV.generate(headers: true) do |csv|
      csv << [ "Username", "Email", "Guild", "Role", "Status", "Discord Username", "Tags" ]
      alliance_members.each do |member|
        csv << [
          member.user.username,
          member.user.email,
          member.guild&.name,
          member.role,
          member.status,
          member.user.user_discord_connection&.discord_username,
          member.alliance_tags.order(:name).pluck(:name).join("|")
        ]
      end
    end
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
