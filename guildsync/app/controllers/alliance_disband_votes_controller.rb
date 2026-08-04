# frozen_string_literal: true

class AllianceDisbandVotesController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_gm

  def index
    preserve_session
    @votes       = @alliance.alliance_disband_votes.includes(:user, :guild)
    @total_guilds = @alliance.alliance_guilds.where(status: :active).count
    @my_vote      = @alliance.alliance_disband_votes.find_by(guild_id: @my_guild.id)
  end

  def create
    preserve_session
    existing = @alliance.alliance_disband_votes.find_by(guild_id: @my_guild.id)
    if existing
      existing.update!(vote: params[:vote].to_s == "true")
    else
      @alliance.alliance_disband_votes.create!(
        user:    current_user,
        guild:   @my_guild,
        vote:    params[:vote].to_s == "true"
      )
    end

    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: @my_guild,
      action_type: "alliance_disband_vote",
      description: %(Disband vote cast (#{params[:vote].to_s == "true" ? "yes" : "no"}) for guild "#{@my_guild.name}"),
      **AllianceActivityLogger.guild_context_metadata(@my_guild)
    )

    if @alliance.majority_voted_to_disband?
      AllianceActivityLogger.log(
        alliance: @alliance,
        user: current_user,
        guild: @alliance.leader_guild,
        action_type: "alliance_disbanded",
        description: %(Alliance "#{@alliance.name}" was disbanded by majority vote),
        **AllianceActivityLogger.guild_context_metadata(@alliance.leader_guild)
      )
      @alliance.disband!
      redirect_to dashboard_path, notice: t("alliances.disband_votes.majority_disbanded")
    else
      redirect_to alliance_alliance_disband_votes_path(@alliance), notice: t("alliances.disband_votes.vote_cast")
    end
  end

  private

  def require_gm
    @my_guild = current_user.owned_guilds.find do |guild|
      @alliance.active_guild_ids.include?(guild.id)
    end

    unless @my_guild
      redirect_to alliance_path(@alliance), alert: t("alliances.disband_votes.errors.not_gm")
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
