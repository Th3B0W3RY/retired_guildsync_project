class DiscordConnectionsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :set_guild, except: [ :oauth_callback ]
  before_action :require_active_guild_access, except: [ :oauth_callback ]
  before_action :set_guild_from_session, only: [ :oauth_callback ]
  before_action :require_active_guild_access, only: [ :oauth_callback ]
  skip_before_action :authenticate_user!, only: [ :oauth_callback ]

  def show
    if params[:bot] == "authorized"
      flash.now[:notice] = "GuildSync bot authorized successfully. Events and Discord features are now enabled for this server."
    end
    # Ensure session is preserved throughout the action
    if current_user.present?
      session[:user_id] = current_user.id
      if session[:mfa_verified]
        session[:mfa_verified_at] = Time.current.to_i
      end
      session.save if session.respond_to?(:save)
    end

    @user_conn = current_user.user_discord_connection
    @connected = @user_conn.present?
    
    # Clear any stale error messages if Discord is connected successfully
    if @connected && flash[:alert]&.include?("Failed to fetch Discord servers")
      flash.delete(:alert)
    end

    # Check if bot is actually in the Discord server
    @bot_connected = false
    if @guild.guild_discord_setting&.discord_guild_id.present?
      begin
        bot_service = DiscordService.new(bot_token: ENV["DISCORD_BOT_TOKEN"])
        bot_service.get_guild(@guild.guild_discord_setting.discord_guild_id)
        @bot_connected = true
      rescue => e
        Rails.logger.warn "Bot not in Discord server: #{e.message}"
        @bot_connected = false
      end

      # Generate bot invite URL if bot is not connected
      # Use the SELECTED server's discord_guild_id to pre-select it in the authorization popup
      unless @bot_connected
        selected_server_id = @guild.guild_discord_setting&.discord_guild_id

        if selected_server_id.present?
          session[:bot_auth_guild_id] = @guild.id
          @bot_invite_url = bot_authorization_url(selected_server_id)
          @discord_bot_redirect_uri = guild_bot_oauth_redirect_uri
          @discord_bot_client_id = ENV["DISCORD_BOT_CLIENT_ID"] || ENV["DISCORD_CLIENT_ID"]
          Rails.logger.info "Generated bot invite URL with guild_id: #{selected_server_id} for server: #{@guild.guild_discord_setting.discord_guild_name}"
        else
          @bot_invite_url = nil
          @discord_bot_redirect_uri = nil
          @discord_bot_client_id = nil
        end
      end
    end
  end

  def create
    if current_user.has_valid_discord_connection?
      redirect_to select_discord_server_path(@guild)
      return
    end

    redirect_uri = guild_bot_oauth_redirect_uri
    state = SecureRandom.hex(16)

    session[:discord_oauth_state] = state
    session[:discord_oauth_guild_id] = @guild.id
    session[:discord_oauth_popup] = params[:popup].present?

    url = DiscordService.new.authorization_url(redirect_uri, state)
    redirect_to url, allow_other_host: true
  end

  def oauth_callback
    if params[:error]
      # For bot authorization errors, just close popup
      if session[:bot_auth_guild_id].present?
        session.delete(:bot_auth_guild_id)
        log_security_event(event: "discord.bot_authorization", status: "failure", actor: nil, metadata: { error: params[:error].to_s })
        render inline: "<script>window.close();</script>", layout: false
        return
      end
      log_security_event(event: "auth.discord_oauth", status: "failure", actor: nil, metadata: { error: params[:error].to_s })
      redirect_to my_guilds_path, alert: t("controllers.discord_connections.authorization_failed")
      return
    end

    # Check if this is a bot authorization (session has bot_auth_guild_id)
    if session[:bot_auth_guild_id].present?
      guild_id = session[:bot_auth_guild_id]
      session.delete(:bot_auth_guild_id)
      return bot_callback_handler(guild_id)
    end

    # This is a user OAuth callback
    if params[:state] != session[:discord_oauth_state]
      redirect_to my_guilds_path, alert: t("controllers.discord_connections.invalid_state")
      return
    end

    return redirect_to my_guilds_path, alert: t("controllers.discord_connections.guild_lost") unless @guild

    # Get user from session if current_user is not available (popup scenario)
    user = current_user || (session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil)
    unless user
      if session[:discord_oauth_popup] || params[:popup].present?
        message_json = t("controllers.discord_connections.sign_in_first").to_json
        render inline: "<script>(function(){var msg=#{message_json};if(window.showToast){window.showToast('error',msg);}else{alert(msg);}setTimeout(function(){window.close();},2500);})();</script>", layout: false
      else
        redirect_to my_guilds_path, alert: t("controllers.discord_connections.sign_in_first")
      end
      return
    end

    # Same capability as connect / server-select: do not exchange the code if permission was revoked
    # after authorize (or session was tampered with).
    unless can_manage_discord_channels?(@guild, user)
      alert = t("controllers.guilds.permissions.discord_channels_denied")
      if session[:discord_oauth_popup] || params[:popup].present?
        message_json = alert.to_json
        render inline: "<script>(function(){var msg=#{message_json};if(window.showToast){window.showToast('error',msg);}else{alert(msg);}setTimeout(function(){window.close();},2500);})();</script>", layout: false
      else
        redirect_to guild_path(@guild), alert: alert
      end
      return
    end

    redirect_uri = guild_bot_oauth_redirect_uri
    service = DiscordService.new
    token = service.exchange_code_for_token(params[:code], redirect_uri)
    user_info = service.get_user_info(token["access_token"])

    # Find or initialize by discord_user_id to avoid unique constraint violations
    # If a connection exists with this discord_user_id, update it (handles reconnections)
    conn = UserDiscordConnection.find_or_initialize_by(discord_user_id: user_info["id"])
    conn.user = user
    conn.update!(
      discord_username: user_info["username"],
      access_token: token["access_token"],
      refresh_token: token["refresh_token"],
      expires_at: Time.current + token["expires_in"].to_i.seconds
    )

    if user_info["global_name"].present?
      user.update!(discord_global_name: user_info["global_name"])
    end

    log_security_event(
      event: "auth.discord_oauth",
      status: "success",
      actor: user,
      metadata: { guild_id: @guild&.id, discord_user_id: user_info["id"] }
    )

    # Preserve popup flag from session
    is_popup = session[:discord_oauth_popup] || params[:popup].present?
    if is_popup
      # Close popup and redirect main window to server selection
      render inline: <<~HTML, layout: false
        <!DOCTYPE html>
        <html>
        <head>
          <title>Discord Connected</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              display: flex;
              justify-content: center;
              align-items: center;
              height: 100vh;
              margin: 0;
              background: #1a1a1a;
              color: #ffffff;
            }
            .message {
              text-align: center;
              padding: 20px;
            }
          </style>
        </head>
        <body>
          <div class="message">
            <p>Discord account connected successfully! Closing window...</p>
          </div>
          <script>
            (function() {
              var sendMessage = function() {
                if (window.opener && !window.opener.closed) {
                  try {
                    window.opener.postMessage({ 
                      type: 'DISCORD_USER_CONNECTED', 
                      redirect: '<%= select_discord_server_path(@guild) %>' 
                    }, '*');
                    console.log('Discord user connected message sent to opener');
                  } catch (e) {
                    console.error('Error sending message:', e);
                  }
                }
              };

              // Send message multiple times to ensure delivery
              sendMessage();
              setTimeout(sendMessage, 100);
              setTimeout(sendMessage, 300);
              setTimeout(sendMessage, 500);

              // Close popup after ensuring message is sent
              setTimeout(function() {
                try {
                  window.close();
                } catch (e) {
                  console.error('Error closing window:', e);
                }
              }, 800);
            })();
          </script>
        </body>
        </html>
      HTML
    else
      # When not in popup, redirect to server selection with success message and flag so select_server shows the green notice
      redirect_to select_discord_server_path(@guild, from: "oauth"), notice: "Discord account connected successfully!"
    end
  ensure
    session.delete(:discord_oauth_state)
    session.delete(:discord_oauth_guild_id)
    # Don't delete popup flag here - it's needed for subsequent redirects
  end

  def select_server
    # Ensure session is preserved throughout the action
    if current_user.present?
      session[:user_id] = current_user.id
      if session[:mfa_verified]
        session[:mfa_verified_at] = Time.current.to_i
      end
      session.save if session.respond_to?(:save)
    end

    conn = current_user.user_discord_connection

    unless conn
      redirect_to guild_discord_connection_path(@guild), alert: t("controllers.discord_connections.connect_discord_first")
      return
    end

    begin
      access = conn.valid_access_token
      guilds = DiscordService.new.get_user_guilds(access, discord_connection: conn)

      # Filter guilds to only show those where user is owner or administrator
      # Discord permissions: 0x8 = ADMINISTRATOR permission
      administrator_permission = 0x8

      @discord_guilds = guilds.select do |g|
        is_owner = g["owner"] == true
        # Handle permissions as string or integer
        permissions = g["permissions"]
        permissions_int = permissions.is_a?(String) ? permissions.to_i : (permissions || 0)
        has_admin = (permissions_int & administrator_permission) == administrator_permission
        is_owner || has_admin
      end.map do |g|
        {
          "id" => g["id"],
          "name" => g["name"],
          "owner" => g["owner"] == true
        }
      end
      
      # Only show success message when user just arrived from OAuth callback (not on every load/refresh)
      if params[:from] == "oauth"
        flash.now[:notice] = "Discord account connected and servers fetched successfully!"
      end
    rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError => e
      redirect_to guild_discord_connection_path(@guild), alert: t("controllers.discord_connections.connection_expired")
      nil
    rescue => e
      Rails.logger.error "Failed to fetch Discord guilds: #{e.class.name}: #{e.message}"
      redirect_to guild_discord_connection_path(@guild), alert: t("controllers.discord_connections.fetch_servers_failed")
      nil
    end
  end

  def connect_server
    # Ensure session is preserved throughout the action
    if current_user.present?
      session[:user_id] = current_user.id
      if session[:mfa_verified]
        session[:mfa_verified_at] = Time.current.to_i
      end
      session.save if session.respond_to?(:save)
    end

    conn = current_user.user_discord_connection

    unless conn
      error_msg = "Connect Discord first"
      if request.xhr? || request.format.json?
        render json: { error: error_msg }, status: :unauthorized
      else
        redirect_to guild_discord_connection_path(@guild), alert: error_msg
      end
      return
    end

    gid = params[:discord_guild_id]
    unless gid
      error_msg = "Please select a Discord server"
      if request.xhr? || request.format.json?
        render json: { error: error_msg }, status: :bad_request
      else
        redirect_to select_discord_server_path(@guild), alert: error_msg
      end
      return
    end

    # verify user belongs to this server
    begin
      guilds = DiscordService.new.get_user_guilds(conn.valid_access_token, discord_connection: conn)
      match = guilds.find { |g| g["id"] == gid }
      unless match
        error_msg = "Server not found"
        if request.xhr? || request.format.json?
          render json: { error: error_msg }, status: :not_found
        else
          redirect_to select_discord_server_path(@guild), alert: error_msg
        end
        return
      end
    rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError => e
      error_msg = "Your Discord connection has expired. Please reconnect your Discord account."
      wants_json = request.xhr? || request.format.json? || request.headers["Accept"].to_s.include?("application/json")
      if wants_json
        render json: { error: error_msg }, status: :unauthorized
      else
        redirect_to guild_discord_connection_path(@guild), alert: error_msg
      end
      return
    rescue => e
      Rails.logger.error "Failed to verify Discord server: #{e.class.name}: #{e.message}"
      error_msg = "Failed to verify Discord server. Please try again."
      wants_json = request.xhr? || request.format.json? || request.headers["Accept"].to_s.include?("application/json")
      if wants_json
        render json: { error: error_msg }, status: :internal_server_error
      else
        redirect_to select_discord_server_path(@guild), alert: error_msg
      end
      return
    end

    # If this Discord server is already linked to another guild, allow transfer if the user owns that guild (or it's orphaned)
    existing = GuildDiscordSetting.find_by(discord_guild_id: gid)
    if existing && existing.guild_id != @guild.id
      other_guild = Guild.find_by(id: existing.guild_id)
      can_take_over = other_guild.nil? || (other_guild.owner_id == current_user.id)
      if can_take_over
        # guild_id is unique: remove @guild's current setting (if any) so we can assign existing to @guild
        current_setting = @guild.guild_discord_setting
        current_setting.destroy if current_setting && current_setting.id != existing.id
        existing.update!(guild_id: @guild.id, discord_guild_name: match["name"], connected_at: nil)
        other_guild&.update_column(:discord_id, nil) if other_guild&.discord_id.present?
        setting = existing
      else
        error_msg = "Server already linked to another guild"
        if request.xhr? || request.format.json? || request.headers["Accept"].to_s.include?("application/json")
          render json: { error: error_msg }, status: :conflict
        else
          redirect_to select_discord_server_path(@guild), alert: error_msg
        end
        return
      end
    else
      setting = @guild.guild_discord_setting || @guild.build_guild_discord_setting
    end

    # Check if bot is already authorized (for test scenarios) BEFORE updating
    bot_already_authorized = setting.persisted? && setting.connected_at.present? && setting.discord_guild_id == gid

    # Set connected_at to nil initially - it will be updated when bot authorization completes
    # UNLESS bot is already authorized (preserve existing connected_at)
    update_params = {
      discord_guild_id: gid,
      discord_guild_name: match["name"]
    }
    update_params[:connected_at] = nil unless bot_already_authorized

    setting.update!(update_params)

    @guild.update_column(:discord_id, gid)

    log_security_event(
      event: "discord.guild_connection",
      status: "success",
      actor: audit_actor,
      subject: @guild,
      metadata: { discord_guild_id: gid, discord_guild_name: match["name"] }
    )

    # Store guild_id in session for bot callback detection
    session[:bot_auth_guild_id] = @guild.id

    # Reload to get updated connected_at
    setting.reload

    # Store guild_id in session for bot callback detection
    session[:bot_auth_guild_id] = @guild.id
    session.save if session.respond_to?(:save)
    
    # Generate bot authorization URL
    bot_auth_url = bot_authorization_url(gid)
    
    # Return JSON when client asks for it (AJAX/fetch) so the page can open the OAuth popup
    wants_json = request.xhr? ||
                 request.format.json? ||
                 request.headers["Accept"].to_s.include?("application/json")
    if wants_json
      render json: {
        success: true,
        bot_auth_url: bot_auth_url,
        server_name: match["name"]
      }
      return
    end

    # Fallback: non-AJAX request (e.g. form submit without JS) — redirect and show notice
    session.save if session.respond_to?(:save)
    redirect_to select_discord_server_path(@guild), notice: "Server selected! Please authorize the bot in the popup."
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
    # Remove the guild's Discord server selection (not the user's Discord connection)
    @guild.guild_discord_setting&.destroy
    @guild.update_column(:discord_id, nil) if @guild.discord_id.present?

    log_security_event(
      event: "discord.guild_disconnect",
      status: "success",
      actor: audit_actor,
      subject: @guild
    )

    # Ensure session is preserved before redirect
    session.save if session.respond_to?(:save)
    redirect_to guild_discord_connection_path(@guild), notice: "Discord server disconnected from this guild"
  end

  def bot_callback_handler(guild_id)
    code = params[:code]

    unless code.present?
      render html: "<script>window.close();</script>".html_safe, layout: false
      return
    end

    # Find the guild from the state (guild_id)
    guild = Guild.find_by(id: guild_id)
    unless guild
      render html: "<script>window.close();</script>".html_safe, layout: false
      return
    end

    user = current_user || (session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil)
    unless user
      render html: "<script>window.close();</script>".html_safe, layout: false
      return
    end

    unless can_manage_discord_channels?(guild, user)
      alert = t("controllers.guilds.permissions.discord_channels_denied")
      render inline: "<script>(function(){var msg=#{alert.to_json};if(window.opener&&typeof window.opener.showToast==='function'){try{window.opener.showToast('error',msg);}catch(e2){alert(msg);}}else{alert(msg);}setTimeout(function(){try{window.close();}catch(e3){}},800);})();</script>", layout: false
      return
    end

    # Exchange code for bot token (Discord requires application/x-www-form-urlencoded)
    redirect_uri = guild_bot_oauth_redirect_uri
    begin
      client_id = ENV["DISCORD_BOT_CLIENT_ID"] || ENV["DISCORD_CLIENT_ID"]
      client_secret = ENV["DISCORD_BOT_CLIENT_SECRET"] || ENV["DISCORD_CLIENT_SECRET"]

      body = {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri
      }
      response = RestClient.post(
        "https://discord.com/api/oauth2/token",
        body.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&"),
        { "Content-Type" => "application/x-www-form-urlencoded" }
      )

      # Exchange successful - Discord automatically adds bot to guild when authorized
      # Ensure guild_discord_setting exists and update connected_at
      setting = guild.guild_discord_setting
      if setting
        setting.update!(connected_at: Time.current)
        Rails.logger.info "Bot authorization successful for guild #{guild_id}, connected_at updated"
        log_security_event(
          event: "discord.bot_authorization",
          status: "success",
          actor: audit_actor,
          subject: guild,
          metadata: { discord_guild_id: setting.discord_guild_id }
        )
      else
        Rails.logger.warn "Bot authorization successful but no guild_discord_setting found for guild #{guild_id}"
      end

      # Render success: if opened in same tab, redirect to guild page; if popup, notify opener and close
      redirect_path = "/guilds/#{guild_id}/discord_connection?bot=authorized"
      render inline: <<~HTML, layout: false
        <!DOCTYPE html>
        <html>
        <head>
          <title>Bot Authorization Success</title>
          <meta charset="UTF-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #1a1a1a; color: #fff; }
            .message { text-align: center; padding: 20px; }
          </style>
        </head>
        <body>
          <div class="message">
            <p>GuildSync bot authorized successfully! Redirecting...</p>
          </div>
          <script>
            (function() {
              var redirectPath = #{redirect_path.to_json};
              if (window.opener && !window.opener.closed) {
                try {
                  window.opener.postMessage({ status: "authorized" }, "*");
                  window.opener.postMessage({ type: "DISCORD_BOT_AUTHORIZED", status: "authorized" }, "*");
                } catch (e) {}
                setTimeout(function() { try { window.close(); } catch (e) {} }, 400);
              } else {
                window.location.replace(redirectPath);
              }
            })();
          </script>
        </body>
        </html>
      HTML
    rescue => e
      log_security_event(
        event: "discord.bot_authorization",
        status: "error",
        actor: audit_actor,
        subject: guild,
        metadata: { error_class: e.class.name }
      )
      Rails.logger.error "Bot authorization callback failed: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      render inline: <<~HTML, layout: false
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Bot Authorization Error</title>
        </head>
        <body>
          <script>
            (function() {
              var errorMessage = #{sanitize_text_input(e.message).to_json};
              alert("Bot authorization failed: " + errorMessage);
              window.close();
            })();
          </script>
        </body>
        </html>
      HTML
    end
  end

  private

  def audit_actor
    current_user
  rescue Devise::MissingWarden
    nil
  end

  def set_guild
    guild_id = params[:guild_id] || params[:id]
    @guild = current_user.guilds.find_by(id: guild_id)
    @guild ||= current_user.owned_guilds.find_by(id: guild_id)
    @guild ||= Guild.find_by(id: guild_id, owner_id: current_user.id)

    unless @guild
      session.save if session.respond_to?(:save)
      redirect_to my_guilds_path, alert: t("controllers.discord_connections.guild_not_found")
      return
    end

    unless can_manage_discord_channels?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t("controllers.guilds.permissions.discord_channels_denied")
      nil
    end
  end

  def set_guild_from_session
    @guild = Guild.find_by(id: session[:discord_oauth_guild_id])
  end

  def bot_authorization_url(guild_id)
    client_id = ENV["DISCORD_BOT_CLIENT_ID"] || ENV["DISCORD_CLIENT_ID"]
    redirect_uri = guild_bot_oauth_redirect_uri
    Rails.logger.info "[Discord bot OAuth] client_id=#{client_id} redirect_uri=#{redirect_uri} (add this exact URL to that app's OAuth2 → Redirects)"

    base = "https://discord.com/oauth2/authorize"
    params = {
      client_id: client_id,
      scope: "bot applications.commands",
      permissions: 8,
      guild_id: guild_id,
      disable_guild_select: true,
      response_type: "code",
      redirect_uri: redirect_uri
    }
    query = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
    "#{base}?#{query}"
  end

  # Redirect URI for guild bot OAuth. Must match exactly what is in Discord Developer Portal (OAuth2 → Redirects) for the BOT application (DISCORD_BOT_CLIENT_ID or DISCORD_CLIENT_ID).
  def guild_bot_oauth_redirect_uri
    raw = if Rails.env.production?
      host = ENV["HOST"].presence || Rails.application.config.action_controller.default_url_options&.dig(:host) || "guild-sync.net"
      protocol = Rails.application.config.action_controller.default_url_options&.dig(:protocol) || "https"
      "#{protocol}://#{host}/discord/oauth/callback"
    else
      "#{request.base_url}/discord/oauth/callback"
    end
    raw.to_s.chomp("/").strip
  end
end
