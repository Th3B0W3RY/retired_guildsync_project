class DiscordEventSignupsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  before_action :verify_webhook_secret!

  def webhook
    event_id = params[:event_id]
    user_id = params[:user_id] || params[:discord_user_id]
    username = params[:username] || params[:discord_username]
    role = params[:role]
    # Use event_action instead of action to avoid Rails reserved param conflict
    event_action = params[:event_action] || "signup"

    unless event_id && user_id && role
      return render json: { error: I18n.t("controllers.discord_event_signups.webhook.missing_required_parameters") }, status: :bad_request
    end

    discord_event = DiscordEvent.find_by(id: event_id)
    unless discord_event
      return render json: { error: I18n.t("controllers.discord_event_signups.webhook.event_not_found") }, status: :not_found
    end

    unless DiscordEvent::ROLE_CATEGORIES.include?(role)
      return render json: { error: I18n.t("controllers.discord_event_signups.webhook.invalid_role") }, status: :bad_request
    end

    begin
      if event_action == "remove" || event_action == "unsignup"
        signup = discord_event.discord_event_signups.find_by(
          discord_user_id: user_id
        )
        signup&.destroy
      else
        # Find or initialize by user_id only (one role per user per event)
        signup = discord_event.discord_event_signups.find_or_initialize_by(
          discord_user_id: user_id
        )
        signup.role = role
        signup.discord_username = username if username.present?
        # Default to on_time if new record
        signup.status = :on_time if signup.new_record? || signup.status.nil?
        signup.save!
      end

      # Count only on_time users
      render json: { success: true, signups_count: discord_event.discord_event_signups.where(status: "on_time").count }
    rescue => e
      Rails.logger.error "Signup webhook error: #{e.message}"
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  private

  def verify_webhook_secret!
    expected_secret = ENV["DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET"].to_s
    provided_secret = request.headers["X-Guildsync-Webhook-Secret"].to_s.presence

    if provided_secret.blank?
      auth_header = request.authorization.to_s
      bearer_prefix = "Bearer "
      provided_secret = auth_header.delete_prefix(bearer_prefix) if auth_header.start_with?(bearer_prefix)
    end

    if expected_secret.blank?
      if Rails.env.production?
        Rails.logger.error("DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET is not set; rejecting webhook request in production")
        return head :unauthorized
      end

      Rails.logger.warn("DISCORD_EVENT_SIGNUPS_WEBHOOK_SECRET is not set; allowing webhook request outside production")
      return
    end

    secret_matches =
      provided_secret.present? &&
      ActiveSupport::SecurityUtils.secure_compare(provided_secret, expected_secret)

    return if secret_matches

    Rails.logger.warn("Unauthorized Discord event signup webhook request")
    head :unauthorized
  end
end
