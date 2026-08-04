class DiscordOAuthController < ApplicationController
  include RequiresActiveGuildAccess

  layout :determine_layout
  before_action :authenticate_user!
  before_action :set_guild, only: [ :authorize, :callback, :select_server, :connect_server ]
  before_action :require_active_guild_access, only: [ :authorize, :callback, :select_server, :connect_server ]
  before_action :ensure_guild_owner, only: [ :authorize, :callback, :connect_server ]
  before_action :validate_oauth_session, only: [ :select_server, :connect_server ]

  def authorize
    # Immediately redirect to Discord OAuth - no page rendering needed
    # Build the redirect URI WITHOUT query parameters - Discord requires exact match
    # We'll get guild_id from session in the callback
    redirect_uri = "#{request.protocol}#{request.host_with_port}/discord/callback"
    state = SecureRandom.hex(16)
    session[:discord_oauth_state] = state
    session[:discord_oauth_guild_id] = @guild.id
    session[:discord_oauth_popup] = params[:popup].present?

    begin
      discord_service = DiscordService.new
      auth_url = discord_service.authorization_url(redirect_uri, state)
      # Redirect immediately to Discord's OAuth page
      redirect_to auth_url, allow_other_host: true
    rescue => e
      Rails.logger.error "Discord OAuth error: #{e.message}"
      # If popup, show error in popup; otherwise redirect with error
      if popup_request?
        render 'callback_error', locals: { error: "Discord integration is not configured. Please contact your administrator to set up Discord integration." }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Discord integration is not configured. Please contact your administrator."
      end
    end
  end

  def callback
    # Check if this is a popup request (from session or params)
    is_popup = session[:discord_oauth_popup] || params[:popup].present?
    
    if params[:error]
      if is_popup
        render 'callback_error', locals: { error: params[:error] }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Discord authorization failed: #{params[:error]}"
      end
      return
    end

    unless params[:state] == session[:discord_oauth_state]
      if is_popup
        render 'callback_error', locals: { error: "Invalid state parameter" }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Invalid state parameter"
      end
      return
    end

    # Build the redirect URI WITHOUT query parameters - must match Discord exactly
    redirect_uri = "#{request.protocol}#{request.host_with_port}/discord/callback"
    
    # Get guild_id from session (set during authorize)
    @guild = Guild.find_by(id: session[:discord_oauth_guild_id])
    unless @guild
      if popup_request?
        render 'callback_error', locals: { error: "Guild not found in session" }, layout: 'popup'
      else
        redirect_to my_guilds_path, alert: "Guild not found."
      end
      return
    end

    begin
      discord_service = DiscordService.new
      token_data = discord_service.exchange_code_for_token(params[:code], redirect_uri)

      # Get user info (with automatic token refresh if needed)
      discord_connection = current_user.discord_connection
      user_info = discord_service.get_user_info(token_data["access_token"], discord_connection: discord_connection)

      # Create or update Discord connection (only one per user)
      discord_connection = current_user.discord_connection
      if discord_connection
        # Update existing connection
        discord_connection.update!(
          discord_user_id: user_info["id"],
          discord_username: "#{user_info['username']}##{user_info['discriminator']}",
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          expires_at: Time.current + token_data["expires_in"].seconds
        )
      else
        # Create new connection
        current_user.create_discord_connection!(
          discord_user_id: user_info["id"],
          discord_username: "#{user_info['username']}##{user_info['discriminator']}",
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          expires_at: Time.current + token_data["expires_in"].seconds
        )
      end

      if user_info["global_name"].present?
        current_user.update!(discord_global_name: user_info["global_name"])
      end

      # Get user's guilds (with automatic token refresh if needed)
      guilds = discord_service.get_user_guilds(token_data["access_token"], discord_connection: discord_connection)

      # Store only minimal data in session to avoid cookie overflow
      # Extract only id and name from each guild object
      session[:discord_access_token] = token_data["access_token"]
      session[:discord_guilds] = guilds.map { |g| { "id" => g["id"], "name" => g["name"] } }

      # Preserve popup flag from session
      is_popup = session[:discord_oauth_popup] || params[:popup].present?
      if is_popup
        redirect_to discord_select_server_path(guild_id: @guild.id, popup: true)
      else
        redirect_to discord_select_server_path(guild_id: @guild.id)
      end
    rescue DiscordTokenExpiredError => e
      Rails.logger.error "Discord token expired: #{e.message}"
      is_popup = session[:discord_oauth_popup] || params[:popup].present?
      if is_popup
        render 'callback_error', locals: { error: "Discord connection expired. Please reconnect your Discord account." }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Discord connection expired. Please reconnect your Discord account."
      end
    rescue => e
      Rails.logger.error "Discord OAuth callback error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      is_popup = session[:discord_oauth_popup] || params[:popup].present?
      if is_popup
        render 'callback_error', locals: { error: "Failed to connect Discord account: #{e.message}" }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Failed to connect Discord account: #{e.message}"
      end
    ensure
      session.delete(:discord_oauth_state)
    end
  end

  def select_server
    @discord_guilds = session[:discord_guilds] || []
    @access_token = session[:discord_access_token]

    unless @access_token.present? && @discord_guilds.present?
      redirect_to guild_connect_discord_path(@guild), alert: "OAuth session expired. Please start over."
      return
    end

    if @discord_guilds.empty?
      redirect_to guild_connect_discord_path(@guild), alert: "No Discord servers found. Please make sure you're a member of at least one server."
    end
  end

  def connect_server
    discord_guild_id = params[:discord_guild_id]
    access_token = session[:discord_access_token]

    unless discord_guild_id && access_token
      if popup_request?
        render 'callback_error', locals: { error: "Missing required parameters" }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Missing required parameters"
      end
      return
    end

    begin
      discord_service = DiscordService.new

      # Find the selected guild from session
      selected_guild = session[:discord_guilds]&.find { |g| g["id"] == discord_guild_id }

      unless selected_guild
        if popup_request?
          render 'callback_error', locals: { error: "Discord server not found" }, layout: 'popup'
        else
          redirect_to guild_connect_discord_path(@guild), alert: "Discord server not found"
        end
        return
      end

      # Check if this Discord server is already connected to another guild
      existing_setting = GuildDiscordSetting.find_by(discord_guild_id: discord_guild_id)
      if existing_setting && existing_setting.guild != @guild
        if popup_request?
          render 'callback_error', locals: { error: "This Discord server is already connected to another guild." }, layout: 'popup'
        else
          redirect_to guild_connect_discord_path(@guild), alert: "This Discord server is already connected to another guild."
        end
        return
      end

      # Create or update guild Discord settings (only one per guild)
      discord_setting = @guild.guild_discord_setting
      if discord_setting
        # Update existing setting
        discord_setting.update!(
          discord_guild_id: discord_guild_id,
          discord_guild_name: selected_guild["name"],
          bot_token: ENV["DISCORD_BOT_TOKEN"],
          connected_at: Time.current
        )
      else
        # Create new setting
        @guild.create_guild_discord_setting!(
          discord_guild_id: discord_guild_id,
          discord_guild_name: selected_guild["name"],
          bot_token: ENV["DISCORD_BOT_TOKEN"],
          connected_at: Time.current
        )
      end

      # Generate bot invite URL
      client_id = ENV["DISCORD_CLIENT_ID"]
      permissions = 0x8  # Administrator permission
      redirect_uri = "#{request.protocol}#{request.host_with_port}/discord/callback"
      # Include guild_id and disable_guild_select so the selected server is
      # pre-selected in Discord's authorization UI, matching the per-guild
      # connection flow.
      invite_url = "https://discord.com/oauth2/authorize" \
                   "?client_id=#{client_id}" \
                   "&scope=#{CGI.escape('bot applications.commands')}" \
                   "&permissions=#{permissions}" \
                   "&guild_id=#{discord_guild_id}" \
                   "&disable_guild_select=true" \
                   "&response_type=code" \
                   "&redirect_uri=#{CGI.escape(redirect_uri)}"

      # Queue job to verify bot join
      DiscordBotJoinJob.perform_later(@guild.id, discord_guild_id)

      # Clear session
      session.delete(:discord_access_token)
      session.delete(:discord_guilds)
      session.delete(:discord_oauth_popup)

      if popup_request?
        render 'callback_success', locals: { invite_url: invite_url }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), notice: "Discord server connected! Please add the bot to your server using this link: #{invite_url}"
      end
    rescue => e
      Rails.logger.error "Discord server connection error: #{e.message}"
      if popup_request?
        render 'callback_error', locals: { error: "Failed to connect Discord server: #{e.message}" }, layout: 'popup'
      else
        redirect_to guild_connect_discord_path(@guild), alert: "Failed to connect Discord server: #{e.message}"
      end
    end
  end

  private

  def determine_layout
    popup_request? ? 'popup' : 'application'
  end

  def popup_request?
    params[:popup].present? || session[:discord_oauth_popup] || request.referer&.include?('popup=true')
  end

  def set_guild
    guild_id = params[:guild_id] || params[:id]
    @guild = Guild.find_by(id: guild_id)
    unless @guild
      redirect_to my_guilds_path, alert: "Guild not found."
      return
    end
  end

  def ensure_guild_owner
    unless @guild
      redirect_to my_guilds_path, alert: "Guild not found."
      return
    end
    
    unless @guild.owner_id == current_user.id
      redirect_to guild_path(@guild), alert: "Only the guild owner can manage Discord settings."
      return
    end
  end

  def validate_oauth_session
    unless session[:discord_access_token].present? && session[:discord_guilds].present?
      redirect_to guild_connect_discord_path(@guild), alert: "OAuth session expired. Please start over."
    end
  end
end
