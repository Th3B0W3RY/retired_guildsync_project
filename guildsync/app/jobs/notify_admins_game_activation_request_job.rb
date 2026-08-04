# frozen_string_literal: true

# Background job to notify admins when a new game activation request is created
# This job sends Discord DMs to all admin users when a game is created as inactive
#
# Usage:
#   NotifyAdminsGameActivationRequestJob.perform_later(game_id, requester_id)
#
# Note: Only notifies admins who have Discord connections
class NotifyAdminsGameActivationRequestJob < ApplicationJob
  queue_as :default

  def perform(game_id, requester_id = nil)
    game = Game.find_by(id: game_id)
    return unless game
    
    # Only notify for inactive games (activation requests)
    return if game.active?
    
    requester = requester_id ? User.find_by(id: requester_id) : nil
    requester_name = requester ? (requester.display_name.presence || requester.username || requester.email) : "A user"
    
    # Get all admin users
    admin_users = get_admin_users
    return if admin_users.empty?
    
    # Build message
    game_url = Rails.application.routes.url_helpers.game_url(
      game,
      host: ENV['HOST'] || ENV['APP_HOST'] || 'localhost:5000'
    )
    
    message = "🎮 **New Game Activation Request**\n\n"
    message += "**Game:** #{game.name}\n"
    message += "**Requested by:** #{requester_name}\n"
    if game.description.present?
      message += "**Description:** #{game.description.truncate(200)}\n"
    end
    message += "\n[Review and activate → #{game_url}]"
    
    # Send notifications to all admins with Discord connections
    discord_service = DiscordService.new
    notified_count = 0
    failed_count = 0
    
    admin_users.each do |admin|
      discord_connection = admin.user_discord_connection
      next unless discord_connection&.discord_user_id.present?
      
      begin
        discord_service.send_dm(discord_connection.discord_user_id, message)
        notified_count += 1
        Rails.logger.info "Sent game activation request notification to admin #{admin.email} (Discord ID: #{discord_connection.discord_user_id})"
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to send game activation request notification to admin #{admin.email}: #{e.message}"
      end
    end
    
    Rails.logger.info "Game activation request notifications: #{notified_count} sent, #{failed_count} failed for game #{game.name} (ID: #{game.id})"
    
    { notified: notified_count, failed: failed_count, total_admins: admin_users.count }
  end
  
  private
  
  def get_admin_users
    admin_users = []
    
    # Get admins by email
    admin_emails = ENV.fetch('ADMIN_EMAILS', '').split(',').map(&:strip).reject(&:blank?)
    admin_emails.each do |email|
      user = User.find_by(email: email)
      admin_users << user if user
    end
    
    # Get admins by user ID
    admin_user_ids = ENV.fetch('ADMIN_USER_IDS', '').split(',').map(&:strip).reject(&:blank?).map(&:to_i)
    admin_user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      admin_users << user if user
    end
    
    # Remove duplicates and return
    admin_users.uniq
  end
end

