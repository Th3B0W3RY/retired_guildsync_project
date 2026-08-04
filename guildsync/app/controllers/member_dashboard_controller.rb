class MemberDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mfa_if_enabled

  def index
    preserve_session
    # Show all available guilds that users can apply to
    @applications = current_user.guild_applications.includes(:guild).order(created_at: :desc)
    @accepted_guilds = current_user.guilds.joins(:guild_members).where(guild_members: { status: :active }).distinct
    # Show all available guilds (for browsing/applying)
    @available_guilds = available_guilds_by_game(current_user)
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  # Public, non-archived guilds (same set as guild application targeting).
  # The `game` argument is reserved for future game-based filtering.
  def available_guilds_by_game(_user, game = nil)
    scope = Guild.discoverable_for_applications.order(:name)
    return scope if game.blank?

    scope # TODO: filter by game when that feature is implemented
  end
end
