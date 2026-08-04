class LeaderboardController < ApplicationController
  before_action :authenticate_user!

  def index
    preserve_session
    # Get all guilds the user has access to
    user_guild_ids = current_user.guilds.pluck(:id)
    
    return @leaderboard_data = [] if user_guild_ids.empty?

    @leaderboard_data = Guilds::MemberLeaderboardScores.call(user_guild_ids: user_guild_ids)
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end

