# frozen_string_literal: true

class AllianceLootRollsController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member
  before_action :set_loot_roll, only: [ :show, :destroy, :close, :enter ]
  before_action :require_can_manage, only: [ :new, :create, :destroy, :close ]

  def index
    preserve_session
    @loot_rolls = @alliance.alliance_loot_rolls.ordered
  end

  def show
    preserve_session
    @entries     = @loot_roll.alliance_loot_roll_entries.order(roll_value: :desc)
    @my_entry    = @loot_roll.alliance_loot_roll_entries.find_by(user: current_user)
  end

  def new
    preserve_session
    @loot_roll = @alliance.alliance_loot_rolls.build(min_roll: 1, max_roll: 100)
  end

  def create
    preserve_session
    @loot_roll = @alliance.alliance_loot_rolls.build(loot_roll_params)
    @loot_roll.creator = current_user

    if @loot_roll.save
      AllianceDiscordBroadcastService.broadcast_alliance_loot_roll_created(@alliance, @loot_roll)
      redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), notice: t("alliances.loot_rolls.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    preserve_session
    @loot_roll.soft_delete!
    redirect_to alliance_alliance_loot_rolls_path(@alliance), notice: t("alliances.loot_rolls.deleted")
  end

  def close
    preserve_session
    unless @loot_roll.open?
      redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), alert: t("alliances.loot_rolls.errors.already_closed")
      return
    end

    @loot_roll.close_and_determine_winner!
    begin
      DiscordAllianceLootRollService.update_all_linked_messages(@loot_roll.reload)
    rescue StandardError => e
      Rails.logger.warn "[AllianceLootRollsController#close] Discord update failed: #{e.class}: #{e.message}"
    end
    begin
      AllianceLootRollsChannel.broadcast_update(@loot_roll.reload)
    rescue StandardError => e
      Rails.logger.warn "[AllianceLootRollsController#close] Action Cable broadcast failed: #{e.class}: #{e.message}"
    end
    redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), notice: t("alliances.loot_rolls.closed")
  end

  def enter
    preserve_session
    unless @loot_roll.currently_open?
      redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), alert: t("alliances.loot_rolls.errors.not_open")
      return
    end

    entry = @loot_roll.alliance_loot_roll_entries.find_or_initialize_by(user: current_user)
    if entry.persisted?
      redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), alert: t("alliances.loot_rolls.errors.already_entered")
      return
    end

    entry.save!
    begin
      DiscordAllianceLootRollService.update_all_linked_messages(@loot_roll.reload)
    rescue StandardError => e
      Rails.logger.warn "[AllianceLootRollsController#enter] Discord update failed: #{e.class}: #{e.message}"
    end
    begin
      AllianceLootRollsChannel.broadcast_update(@loot_roll.reload)
    rescue StandardError => e
      Rails.logger.warn "[AllianceLootRollsController#enter] Action Cable broadcast failed: #{e.class}: #{e.message}"
    end
    redirect_to alliance_alliance_loot_roll_path(@alliance, @loot_roll), notice: t("alliances.loot_rolls.entered", roll: entry.roll_value)
  end

  private

  def set_loot_roll
    @loot_roll = @alliance.alliance_loot_rolls.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_loot_rolls_path(@alliance), alert: t("alliances.loot_rolls.errors.not_found")
  end

  def require_can_manage
    return if can_manage_alliance_actions?(@alliance)

    redirect_to alliance_alliance_loot_rolls_path(@alliance), alert: t("alliances.loot_rolls.errors.manage_unauthorized")
  end

  def loot_roll_params
    params.require(:alliance_loot_roll).permit(:title, :description, :min_roll, :max_roll, :anonymous, :deadline_at)
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
