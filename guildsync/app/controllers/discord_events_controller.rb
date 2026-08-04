class DiscordEventsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_manage_events_permission

  def new
    @user_conn = current_user.user_discord_connection
    @discord_guild_id = @guild.discord_id || @guild.guild_discord_setting&.discord_guild_id

    # Check if bot is actually in the Discord server
    @bot_connected = false
    if @discord_guild_id.present?
      begin
        bot_service = DiscordService.new(bot_token: ENV["DISCORD_BOT_TOKEN"])
        bot_service.get_guild(@discord_guild_id)
        @bot_connected = true
      rescue => e
        Rails.logger.warn "Bot not in Discord server: #{e.message}"
        @bot_connected = false
      end
    end

    unless @user_conn&.access_token.present? && @discord_guild_id.present? && @bot_connected
      redirect_to guild_schedule_events_path(@guild), alert: "Please connect Discord first."
      return
    end

    @discord_setting = @guild.guild_discord_setting
    unless @discord_setting&.events_channel_configured?
      redirect_to guild_settings_path(@guild), alert: "Please configure an Events Channel in Settings before creating events."
      nil
    end

    @synced_roles = @guild.discord_role_syncs.order(:role_name)
  end

  def create
    # Ensure session is preserved throughout the action
    if current_user.present?
      session[:user_id] = current_user.id
      if session[:mfa_verified]
        session[:mfa_verified_at] = Time.current.to_i
      end
      session.save if session.respond_to?(:save)
    end
    
    @user_conn = current_user.user_discord_connection
    @discord_guild_id = @guild.discord_id || @guild.guild_discord_setting&.discord_guild_id

    # Check if bot is actually in the Discord server
    @bot_connected = false
    if @discord_guild_id.present?
      begin
        bot_service = DiscordService.new(bot_token: ENV["DISCORD_BOT_TOKEN"])
        bot_service.get_guild(@discord_guild_id)
        @bot_connected = true
      rescue => e
        Rails.logger.warn "Bot not in Discord server: #{e.message}"
        @bot_connected = false
      end
    end

    unless @user_conn&.access_token.present? && @discord_guild_id.present? && @bot_connected
      redirect_to guild_schedule_events_path(@guild), alert: "Discord connection is invalid. Please reconnect."
      return
    end

    @discord_setting = @guild.guild_discord_setting
    unless @discord_setting&.events_channel_configured?
      redirect_to guild_settings_path(@guild), alert: "Please configure an Events Channel in Settings before creating events."
      return
    end

    events_channel_id = @discord_setting.events_channel_id

    # Get timezone from params or default to UTC
    timezone = params[:timezone].presence || "UTC"

    begin
      # Parse the date and time in the user's timezone
      date_str = params[:date]
      time_str = params[:time]

      unless date_str.present? && time_str.present?
        redirect_to new_guild_discord_event_path(@guild), alert: "Date and time are required."
        return
      end

      # Create a time in the user's timezone
      tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["UTC"]
      local_time = tz.parse("#{date_str} #{time_str}")

      # Convert to UTC for storage and Discord (Discord requires UTC)
      scheduled_at = local_time.utc
    rescue => e
      Rails.logger.error "Time parsing error: #{e.message}"
      redirect_to new_guild_discord_event_path(@guild), alert: "Invalid date or time format: #{e.message}"
      return
    end

    # Handle custom event type
    event_type = params[:event_type]
    if event_type == "custom"
      custom_type = discord_event_params[:custom_event_type]
      if custom_type.blank?
        redirect_to new_guild_discord_event_path(@guild), alert: "Please enter a custom event type name."
        return
      end
      event_type = custom_type
    end

    bot_token = @discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
    service = DiscordService.new(bot_token: bot_token)

    begin
      # Prevent duplicate event creation - check if event with same title and time already exists
      existing_event = @guild.discord_events.find_by(
        title: discord_event_params[:title],
        scheduled_at: scheduled_at
      )

      if existing_event
        redirect_to guild_discord_event_path(@guild, existing_event), notice: "Event already exists."
        return
      end

      discord_event_id = service.create_scheduled_event!(
        guild: @guild,
        channel_id: events_channel_id,
        name: discord_event_params[:title],
        description: discord_event_params[:description],
        start_time: scheduled_at,
        event_type: event_type
      )

      # Find or create a discord_connection for this guild (required by model)
      discord_connection = @guild.discord_connection || DiscordConnection.find_or_create_by!(
        guild: @guild,
        user: current_user
      ) do |conn|
        conn.discord_user_id = @user_conn.discord_user_id
        conn.access_token = @user_conn.access_token
        conn.refresh_token = @user_conn.refresh_token
        conn.expires_at = @user_conn.expires_at
      end

      @discord_event = @guild.discord_events.create!(
        discord_connection: discord_connection,
        discord_event_id: discord_event_id,
        channel_id: events_channel_id,
        title: discord_event_params[:title],
        description: discord_event_params[:description],
        event_type: event_type,
        scheduled_at: scheduled_at,
        timezone: timezone,
        max_participants: discord_event_params[:max_participants].presence&.to_i,
        role_categories: params[:roles] || [],
        squad_leader: discord_event_params[:squad_leader].presence,
        location: discord_event_params[:location].presence,
        discord_role_mentions: params[:discord_role_mentions] || []
      )

      message_id = service.post_event_signup_message!(@discord_event, roles: params[:roles] || [])
      @discord_event.update!(discord_message_id: message_id) if message_id

      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "event_created", description: "Created event \"#{discord_event_params[:title]}\"", subject: @discord_event, title: discord_event_params[:title])
      # Ensure session is preserved before redirect
      session.save if session.respond_to?(:save)
      redirect_to guild_discord_event_path(@guild, @discord_event), notice: "Event created successfully!"
    rescue => e
      Rails.logger.error "Failed to create Discord event: #{e.message}\n#{e.backtrace.join("\n")}"
      # Ensure session is preserved before redirect
      session.save if session.respond_to?(:save)
      redirect_to new_guild_discord_event_path(@guild), alert: "Failed to create event: #{e.message}"
    end
  end

  def show
    @discord_event = @guild.discord_events.find(params[:id])
    @signups_by_role = @discord_event.signups_by_role
    @role_emojis = DiscordEvent::ROLE_EMOJIS
  end

  def destroy
    # Ensure session is preserved throughout the action
    if current_user.present?
      session[:user_id] = current_user.id
      if session[:mfa_verified]
        session[:mfa_verified_at] = Time.current.to_i
      end
      session.save if session.respond_to?(:save)
    end
    
    @discord_event = @guild.discord_events.find(params[:id])

    begin
      discord_guild_id = @guild.discord_id || @guild.guild_discord_setting&.discord_guild_id
      bot_token = @guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
      service = DiscordService.new(bot_token: bot_token)

      # Delete Discord scheduled event
      if discord_guild_id && @discord_event.discord_event_id
        begin
          RestClient.delete(
            "#{DiscordService::DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events/#{@discord_event.discord_event_id}",
            { "Authorization" => "Bot #{bot_token}" }
          )
          Rails.logger.info "Deleted Discord scheduled event: #{@discord_event.discord_event_id}"
        rescue => e
          Rails.logger.warn "Failed to delete Discord scheduled event: #{e.message}"
        end
      end

      # Delete Discord message
      if @discord_event.channel_id && @discord_event.discord_message_id
        begin
          service.delete_message(@discord_event.channel_id, @discord_event.discord_message_id)
          Rails.logger.info "Deleted Discord message: #{@discord_event.discord_message_id}"
        rescue => e
          Rails.logger.warn "Failed to delete Discord message: #{e.message}"
        end
      end

      event_title = @discord_event.title
      @discord_event.soft_delete!
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "event_deleted", description: "Deleted event \"#{event_title}\"", title: event_title)
      # Ensure session is preserved before redirect
      session.save if session.respond_to?(:save)
      redirect_to guild_schedule_events_path(@guild), notice: "Event deleted successfully."
    rescue => e
      Rails.logger.error "Failed to delete event: #{e.message}"
      # Ensure session is preserved before redirect
      session.save if session.respond_to?(:save)
      redirect_to guild_discord_event_path(@guild, @discord_event), alert: "Failed to delete event: #{e.message}"
    end
  end

  private

  def set_guild
    guild_id = params[:guild_id] || params[:id]
    @guild = current_user.guilds.find_by(id: guild_id) ||
             current_user.owned_guilds.find_by(id: guild_id) ||
             Guild.find_by(id: guild_id, owner_id: current_user.id)
    unless @guild
      redirect_to my_guilds_path, alert: "Guild not found or you do not have access to it."
    end
  end

  def require_manage_events_permission
    unless @guild && can_manage_events?(@guild)
      redirect_to (@guild ? guild_path(@guild) : my_guilds_path), alert: "You do not have permission to manage Discord events."
    end
  end

  def discord_event_params
    permitted = params.permit(
      :title,
      :description,
      :custom_event_type,
      :max_participants,
      :squad_leader,
      :location
    )
    sanitize_permitted_text_fields!(permitted, [:title, :description, :custom_event_type, :squad_leader, :location])
  end
end
