require "rest-client"
require "json"
require "openssl"
require "cgi"

class DiscordService
  DISCORD_API_BASE = "https://discord.com/api/v10"
  DISCORD_OAUTH_BASE = "https://discord.com/api/oauth2"

  def initialize(bot_token: nil)
    @bot_token = bot_token || ENV["DISCORD_BOT_TOKEN"]
  end

  # Use Discord logger for all Discord-related logging
  def discord_logger
    @discord_logger ||= defined?(DiscordLogger) ? DiscordLogger : Rails.logger
  end

  # OAuth2 Methods
  def authorization_url(redirect_uri, state = nil, guild_id: nil, for_bot: false)
    client_id = ENV["DISCORD_CLIENT_ID"]

    unless client_id.present?
      raise "DISCORD_CLIENT_ID environment variable is not set. Please configure it in your .env file."
    end

    # For user account connection: only identify and guilds scopes (no bot permissions)
    # For bot authorization: bot and applications.commands scopes with permissions
    if for_bot
      scopes = %w[identify guilds bot applications.commands].join(" ")
      permissions = 0x8  # Administrator permission
    else
      scopes = %w[identify guilds].join(" ")
      permissions = nil  # No permissions for user-only OAuth
    end

    # Use GuildSync DEVELOPMENT server ID if available, otherwise use provided guild_id
    target_guild_id = guild_id || ENV["DISCORD_GUILDSYNC_DEVELOPMENT_SERVER_ID"]

    params = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scopes,
      state: state
    }

    # Only add permissions and guild_id for bot authorization
    if for_bot
      params[:permissions] = permissions
      # Add guild_id to pre-select the server (this makes the bot automatically join that server)
      params[:guild_id] = target_guild_id if target_guild_id.present?
    end

    query_string = params.compact.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
    "#{DISCORD_OAUTH_BASE}/authorize?#{query_string}"
  end

  def exchange_code_for_token(code, redirect_uri)
    client_id = ENV["DISCORD_CLIENT_ID"]
    client_secret = ENV["DISCORD_CLIENT_SECRET"]

    # Normalize redirect_uri to ensure it matches what Discord expects
    # Remove trailing slashes and ensure consistent format
    normalized_redirect_uri = redirect_uri.to_s.chomp("/")

    discord_logger.info "Exchanging code for token with redirect_uri: #{normalized_redirect_uri}"

    response = RestClient.post(
      "#{DISCORD_OAUTH_BASE}/token",
      {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: "authorization_code",
        code: code,
        redirect_uri: normalized_redirect_uri
      },
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )

    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    discord_logger.error "Discord token exchange failed: #{e.response.code} - #{error_body}"
    discord_logger.error "Request redirect_uri: #{normalized_redirect_uri}"
    # Provide more helpful error message
    if e.response.code == 400
      parsed_error = JSON.parse(error_body) rescue {}
      error_description = parsed_error["error_description"] || parsed_error["error"] || "Bad Request"
      raise "Discord OAuth error: #{error_description}. Please check that your redirect URI matches exactly in Discord's developer portal."
    end
    raise
  end

  def refresh_token(refresh_token)
    body = {
      client_id: ENV["DISCORD_CLIENT_ID"],
      client_secret: ENV["DISCORD_CLIENT_SECRET"],
      grant_type: "refresh_token",
      refresh_token: refresh_token
    }
    post_form("https://discord.com/api/oauth2/token", body)
  end

  def post_form(url, body)
    response = RestClient.post(
      url,
      body,
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord API request failed: #{e.response.body}"
    raise
  end

  def refresh_user_token(discord_connection)
    return nil unless discord_connection.refresh_token.present?

    token_data = refresh_token(discord_connection.refresh_token)
    discord_connection.update!(
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"] || discord_connection.refresh_token,
      expires_at: Time.current + token_data["expires_in"].seconds
    )

    token_data
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord token refresh failed: #{e.response.body}"
    # If refresh fails, mark connection as needing re-authentication
    if e.response.code == 400 || e.response.code == 401
      discord_connection.update_columns(
        access_token: nil,
        refresh_token: nil,
        expires_at: nil
      )
      raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
    end
    raise
  end

  def get_user_info(access_token, discord_connection: nil)
    response = RestClient.get(
      "#{DISCORD_API_BASE}/users/@me",
      { "Authorization" => "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    # If token expired and we have a connection, try to refresh
    if e.response.code == 401 && discord_connection&.refresh_token.present?
      discord_logger.info "Access token expired, attempting refresh"

      # Use the appropriate refresh method based on connection type
      begin
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.refresh!
        else
          refresh_user_token(discord_connection)
        end

        # Reload to ensure we have the latest token
        discord_connection.reload

        # Verify we have a valid access token after refresh
        unless discord_connection.access_token.present?
          raise "Refresh succeeded but access_token is still nil"
        end

        # Retry with new token
        response = RestClient.get(
          "#{DISCORD_API_BASE}/users/@me",
          { "Authorization" => "Bearer #{discord_connection.access_token}" }
        )
        JSON.parse(response.body)
      rescue RestClient::ExceptionWithResponse => refresh_error
        # If refresh API call failed (e.g., invalid refresh token)
        discord_logger.error "Token refresh API failed: #{refresh_error.response.code} - #{refresh_error.response.body}"
        # Delete the connection if refresh failed (access_token is NOT NULL)
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.destroy
        end
        raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
      rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError => refresh_error
        # These errors are already raised by refresh! with connection cleared
        discord_logger.error "Token refresh failed: #{refresh_error.message}"
        raise
      rescue => refresh_error
        discord_logger.error "Token refresh failed: #{refresh_error.class.name}: #{refresh_error.message}"
        # If refresh fails with unexpected error, delete the connection (access_token is NOT NULL)
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.destroy
        end
        raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
      end
    else
      discord_logger.error "Discord user info fetch failed: #{e.response.code} - #{e.response.body}"
      raise
    end
  end

  def get_user_guilds(access_token, discord_connection: nil)
    response = RestClient.get(
      "#{DISCORD_API_BASE}/users/@me/guilds",
      { "Authorization" => "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    # If token expired and we have a connection, try to refresh
    if e.response.code == 401 && discord_connection&.refresh_token.present?
      discord_logger.info "Access token expired, attempting refresh"

      # Use the appropriate refresh method based on connection type
      begin
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.refresh!
        else
          refresh_user_token(discord_connection)
        end

        # Reload to ensure we have the latest token
        discord_connection.reload

        # Verify we have a valid access token after refresh
        unless discord_connection.access_token.present?
          raise "Refresh succeeded but access_token is still nil"
        end

        # Retry with new token
        response = RestClient.get(
          "#{DISCORD_API_BASE}/users/@me/guilds",
          { "Authorization" => "Bearer #{discord_connection.access_token}" }
        )
        JSON.parse(response.body)
      rescue RestClient::ExceptionWithResponse => refresh_error
        # If refresh API call failed (e.g., invalid refresh token)
        discord_logger.error "Token refresh API failed: #{refresh_error.response.code} - #{refresh_error.response.body}"
        # Delete the connection if refresh failed (access_token is NOT NULL)
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.destroy
        end
        raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
      rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError => refresh_error
        # These errors are already raised by refresh! with connection cleared
        discord_logger.error "Token refresh failed: #{refresh_error.message}"
        raise
      rescue => refresh_error
        discord_logger.error "Token refresh failed: #{refresh_error.class.name}: #{refresh_error.message}"
        # If refresh fails with unexpected error, delete the connection (access_token is NOT NULL)
        if discord_connection.is_a?(UserDiscordConnection)
          discord_connection.destroy
        end
        raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
      end
    else
      discord_logger.error "Discord guilds fetch failed: #{e.response.body}"
      raise
    end
  end

  # Bot Methods
  def get_guild(guild_id)
    unless @bot_token.present?
      raise "Bot token is required to fetch guild information"
    end

    response = RestClient.get(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}",
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    result = JSON.parse(response.body)
    discord_logger.info "Fetched Discord guild: #{result["name"]} (ID: #{guild_id})"
    result
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    discord_logger.error "Failed to get Discord guild #{guild_id}: #{e.response.code} - #{error_body}"
    raise
  end

  def get_guild_channels(guild_id, access_token: nil)
    # Use bot token by default, or user access token if provided
    auth_header = if access_token
      "Bearer #{access_token}"
    else
      "Bot #{@bot_token}"
    end

    response = RestClient.get(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/channels",
      { "Authorization" => auth_header }
    )
    channels = JSON.parse(response.body)
    # Filter to only Text Channels (0) and Forum Channels (15)
    channels.select { |c| [ 0, 15 ].include?(c["type"]) }
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord channels fetch failed: #{e.response.body}"
    raise
  end

  def get_guild_roles(guild_id)
    unless @bot_token.present?
      raise "Bot token is required to fetch guild roles"
    end

    response = RestClient.get(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/roles",
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    roles = JSON.parse(response.body)
    discord_logger.info "Fetched #{roles.count} Discord roles for guild: #{guild_id}"
    roles
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    discord_logger.error "Failed to get Discord roles for guild #{guild_id}: #{e.response.code} - #{error_body}"
    raise
  end

  # duration_minutes: when set, scheduled_end_time = start_time + duration; otherwise end is start + 1 hour.
  def create_scheduled_event!(guild:, channel_id:, name:, description:, start_time:, event_type:, duration_minutes: nil)
    discord_guild_id = guild.discord_id || guild.guild_discord_setting&.discord_guild_id
    raise "Guild does not have a Discord server ID" unless discord_guild_id

    # Ensure name and description are present and valid
    name = name.to_s.strip
    description = description.to_s.strip.presence || "Join us for this event!"

    # Check Discord for existing scheduled event with same name and start time (prevent duplicates)
    begin
      existing_events_response = RestClient.get(
        "#{DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events",
        { "Authorization" => "Bot #{@bot_token}" }
      )
      existing_events = JSON.parse(existing_events_response.body)

      # Check if an event with the same name and start time already exists
      start_time_iso = start_time.iso8601
      duplicate = existing_events.find do |event|
        event["name"] == name && event["scheduled_start_time"] == start_time_iso
      end

      if duplicate
        discord_logger.warn "Duplicate Discord scheduled event detected: #{name} at #{start_time_iso}. Returning existing event ID: #{duplicate['id']}"
        return duplicate["id"]
      end
    rescue => e
      discord_logger.warn "Could not check for existing Discord events: #{e.message}. Proceeding with creation."
    end

    # Validate name length (Discord limit is 100 characters)
    if name.length > 100
      raise "Event name is too long (max 100 characters)"
    end

    # Validate description length (Discord limit is 1000 characters)
    if description.length > 1000
      description = description[0..996] + "..."
    end

    # Check if channel is a voice channel (type 2) or text channel (type 0)
    # For text channels, we must use EXTERNAL event type
    # For voice channels, we can use VOICE event type
    channel_type = nil
    if channel_id.present?
      begin
        channel_response = RestClient.get(
          "#{DISCORD_API_BASE}/channels/#{channel_id}",
          { "Authorization" => "Bot #{@bot_token}" }
        )
        channel_data = JSON.parse(channel_response.body)
        channel_type = channel_data["type"]
        discord_logger.info "Channel type detected: #{channel_type} for channel #{channel_id}"
      rescue => e
        discord_logger.warn "Could not fetch channel type: #{e.message}, defaulting to EXTERNAL"
        channel_type = 0 # Assume text channel if we can't fetch
      end
    end

    end_time =
      if duration_minutes.present? && duration_minutes.to_i.positive?
        start_time + duration_minutes.to_i.minutes
      else
        start_time + 1.hour
      end

    # Ensure start_time is in the future
    if start_time < Time.current
      raise "Event start time must be in the future"
    end

    event_data = {
      name: name,
      description: description,
      scheduled_start_time: start_time.iso8601,
      scheduled_end_time: end_time.iso8601,
      privacy_level: 2 # GUILD_ONLY
    }

    # Use VOICE event type only if channel is a voice channel (type 2)
    # Otherwise use EXTERNAL event type (works with text channels)
    if channel_id.present? && channel_type == 2
      # VOICE event - requires channel_id and voice channel
      event_data[:channel_id] = channel_id
      event_data[:entity_type] = 2 # VOICE
    else
      # EXTERNAL event - for text channels, do NOT include channel_id
      event_data[:entity_type] = 3 # EXTERNAL
      event_data[:entity_metadata] = { location: "Discord Server" }
      # Ensure channel_id is NOT in the payload for EXTERNAL events
      event_data.delete(:channel_id)
    end

    discord_logger.info "Creating Discord scheduled event with data: #{event_data.inspect}"

    response = RestClient.post(
      "#{DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events",
      event_data.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    result = JSON.parse(response.body)
    result["id"]
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No error body"
    discord_logger.error "Discord scheduled event creation failed:"
    discord_logger.error "Status: #{e.response.code}"
    discord_logger.error "Response: #{error_body}"
    discord_logger.error "Request data: #{event_data.inspect}" if defined?(event_data)
    raise "Discord API error: #{error_body}"
  end

  def patch_scheduled_event!(guild:, scheduled_event_id:, name: nil, description: nil, start_time: nil, end_time: nil)
    discord_guild_id = guild.discord_id || guild.guild_discord_setting&.discord_guild_id
    raise "Guild does not have a Discord server ID" unless discord_guild_id
    raise "scheduled_event_id required" if scheduled_event_id.blank?

    payload = {}
    payload[:name] = name.to_s.strip if name.present?
    if description
      d = description.to_s.strip.presence || "Join us for this event!"
      d = d[0..996] + "..." if d.length > 1000
      payload[:description] = d
    end
    payload[:scheduled_start_time] = start_time.iso8601 if start_time.present?
    payload[:scheduled_end_time] = end_time.iso8601 if end_time.present?

    return nil if payload.empty?

    RestClient.patch(
      "#{DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events/#{scheduled_event_id}",
      payload.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    true
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord scheduled event patch failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  def delete_scheduled_event!(guild:, scheduled_event_id:)
    discord_guild_id = guild.discord_id || guild.guild_discord_setting&.discord_guild_id
    return false if discord_guild_id.blank? || scheduled_event_id.blank?

    RestClient::Request.execute(
      method: :delete,
      url: "#{DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events/#{scheduled_event_id}",
      headers: { "Authorization" => "Bot #{@bot_token}" }
    )
    true
  rescue RestClient::ExceptionWithResponse => e
    if e.response.code == 404
      discord_logger.warn "Discord scheduled event already deleted: #{scheduled_event_id}"
      return false
    end
    discord_logger.error "Discord scheduled event delete failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  def post_event_signup_message!(discord_event, roles: [])
    return unless discord_event.channel_id.present?

    role_emojis = DiscordEvent::ROLE_EMOJIS

    # Format scheduled time with line break between date and time
    scheduled_time = "<t:#{discord_event.scheduled_at.to_i}:D>\n<t:#{discord_event.scheduled_at.to_i}:t>"

    fields = []

    # Row 1: Squad Leader, Location, Event Type, Total (all inline)
    row1_fields = []
    if discord_event.respond_to?(:squad_leader) && discord_event.squad_leader.present?
      row1_fields << {
        name: "**👤 Squad Leader**",
        value: "**#{discord_event.squad_leader}**",
        inline: true
      }
    end
    if discord_event.respond_to?(:location) && discord_event.location.present?
      row1_fields << {
        name: "**📍 Location**",
        value: "**#{discord_event.location}**",
        inline: true
      }
    end
    row1_fields << {
      name: "**📅 Type**",
      value: "**#{discord_event.event_type&.humanize || "General"}**",
      inline: true
    }
    row1_fields << {
      name: "**👥 Total**",
      value: "**0**",
      inline: true
    }
    fields += row1_fields

    # Add small spacing before roles
    fields << {
      name: "\u200b",
      value: "\u200b",
      inline: false
    }

    # Row 3: Role signups (inline)
    roles.each do |role|
      fields << {
        name: "**#{role_emojis[role]} #{role.upcase}**",
        value: "```None```",
        inline: true
      }
    end

    # Add small spacing before status
    fields << {
      name: "\u200b",
      value: "\u200b",
      inline: false
    }

    # Separator before status
    fields << {
      name: "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
      value: "**STATUS**",
      inline: false
    }
    fields << {
      name: "**❓ Tentative**",
      value: "**None**",
      inline: true
    }
    fields << {
      name: "**⏰ Late**",
      value: "**None**",
      inline: true
    }
    fields << {
      name: "**❌ Absent**",
      value: "**None**",
      inline: true
    }

    # Format scheduled time for description (on same line)
    scheduled_time_formatted = "<t:#{discord_event.scheduled_at.to_i}:F>"
    description_text = discord_event.description || "Join us for this event!"
    description_with_time = "**⏰ Scheduled:** #{scheduled_time_formatted}\n\n#{description_text}"

    server = discord_event.guild.discord_server_display_name
    embed = {
      title: "🎯 #{discord_event.title}",
      description: description_with_time,
      color: 0x5865F2,
      fields: fields,
      timestamp: discord_event.scheduled_at.iso8601,
      footer: {
        text: "GuildSync Event • #{server} • Click buttons below to sign up"
      }
    }

    # Create buttons for each role (max 5 per row)
    # Discord buttons: emoji field requires either a custom emoji ID or standard emoji name
    # For Unicode emojis, we include them in the label instead
    components = []
    if roles.any?
      role_rows = roles.each_slice(5).map do |role_batch|
        {
          type: 1,
          components: role_batch.map do |role|
            {
              type: 2,
              style: 1,
              label: "#{role_emojis[role]} #{role.upcase}",
              custom_id: "event_signup_#{discord_event.id}_#{role}"
            }
          end
        }
      end
      components = role_rows
    end

    # Build role mentions if any are selected
    mentions = ""
    if discord_event.discord_role_mentions.present?
      mentions = discord_event.discord_role_mentions
                   .map { |id| "<@&#{id}>" }
                   .join(" ")
    end

    # Build final message content with mentions
    message_content = if mentions.present?
      "#{mentions}\n\n**New Event Created!** Click the buttons below to sign up by role:"
    else
      "**New Event Created!** Click the buttons below to sign up by role:"
    end

    message = send_message(
      discord_event.channel_id,
      message_content,
      embed: embed,
      components: components
    )

    message["id"]
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord signup message post failed: #{e.response.body}"
    raise
  end


  def send_message(channel_id, content, embed: nil, components: nil, allowed_mentions: nil)
    payload = { content: content }
    payload[:embeds] = [ embed ] if embed
    payload[:components] = components if components
    payload[:allowed_mentions] = allowed_mentions if allowed_mentions.present?

    response = RestClient.post(
      "#{DISCORD_API_BASE}/channels/#{channel_id}/messages",
      payload.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord message send failed: #{e.response.body}"
    raise
  end

  def update_message(channel_id, message_id, content, embed: nil, components: nil, allowed_mentions: nil, retry_count: 0)
    payload = {}
    payload[:content] = content unless content.nil?
    payload[:embeds] = [ embed ] if embed
    payload[:components] = components if components
    payload[:allowed_mentions] = allowed_mentions if allowed_mentions.present?

    response = RestClient.patch(
      "#{DISCORD_API_BASE}/channels/#{channel_id}/messages/#{message_id}",
      payload.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    # Handle rate limits (429) with retry
    if e.response.code == 429 && retry_count < 3
      retry_after = e.response.headers[:retry_after] || e.response.headers["retry-after"]
      wait_time = retry_after ? retry_after.to_f : (2 ** retry_count) # Exponential backoff: 1s, 2s, 4s

      discord_logger.warn "Discord rate limit hit, waiting #{wait_time}s before retry #{retry_count + 1}/3"
      sleep(wait_time)

      # Retry the request
      return update_message(channel_id, message_id, content, embed: embed, components: components, allowed_mentions: allowed_mentions, retry_count: retry_count + 1)
    end

    # Handle 404 (channel/message not found) - expected in test scenarios or if deleted
    if e.response.code == 404
      discord_logger.warn "Discord message/channel not found (404) - message may have been deleted or IDs are invalid"
      return nil
    end

    # Log error but don't raise for rate limits after retries - just fail silently
    if e.response.code == 429
      discord_logger.warn "Discord rate limit exceeded after 3 retries - skipping message update"
      return nil
    end

    discord_logger.error "Discord message update failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  # Create a reaction on a message. Discord requires the emoji to be URL-encoded.
  # For unicode emoji pass the raw character (e.g. "🔥").
  # For custom emoji pass "name:id" (e.g. "LUL:41771983429993937").
  # Handles 429 rate-limits automatically with a single retry.
  def create_reaction(channel_id, message_id, emoji)
    encoded_emoji = CGI.escape(emoji)
    RestClient.put(
      "#{DISCORD_API_BASE}/channels/#{channel_id}/messages/#{message_id}/reactions/#{encoded_emoji}/@me",
      "",
      { "Authorization" => "Bot #{@bot_token}", "Content-Length" => "0" }
    )
    true
  rescue RestClient::ExceptionWithResponse => e
    if e.response.code == 429
      retry_after = (e.response.headers[:retry_after] || e.response.headers["retry-after"] || 1).to_f
      discord_logger.warn "Discord reaction rate-limited, waiting #{retry_after}s"
      sleep(retry_after)
      retry
    end
    discord_logger.error "Discord create reaction failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  # Fetch all custom emojis for a guild (used by the react roles emoji picker).
  # Returns an array of emoji hashes with id, name, animated keys.
  def get_guild_emojis(discord_guild_id)
    response = RestClient.get(
      "#{DISCORD_API_BASE}/guilds/#{discord_guild_id}/emojis",
      { "Authorization" => "Bot #{@bot_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord get guild emojis failed: #{e.response.code} - #{e.response.body}"
    []
  end

  def delete_message(channel_id, message_id)
    RestClient.delete(
      "#{DISCORD_API_BASE}/channels/#{channel_id}/messages/#{message_id}",
      {
        "Authorization" => "Bot #{@bot_token}"
      }
    )
    true
  rescue RestClient::ExceptionWithResponse => e
    # 404 means message already deleted, which is fine
    if e.response.code == 404
      discord_logger.info "Discord message #{message_id} already deleted or not found"
      return true
    end
    discord_logger.error "Discord message delete failed: #{e.response.body}"
    raise
  end

  def create_event_embed(event, image_url: nil)
    # Format scheduled time with line break between date and time
    scheduled_time = "<t:#{event.scheduled_at.to_i}:D>\n<t:#{event.scheduled_at.to_i}:t>"

    fields = []

    # Row 1: Squad Leader, Location, Event Type (all inline)
    row1_fields = []
    if event.respond_to?(:squad_leader) && event.squad_leader.present?
      row1_fields << {
        name: "**👤 Squad Leader**",
        value: "**#{event.squad_leader}**",
        inline: true
      }
    end
    if event.respond_to?(:location) && event.location.present?
      row1_fields << {
        name: "**📍 Location**",
        value: "**#{event.location}**",
        inline: true
      }
    end
    row1_fields << {
      name: "**Event Type**",
      value: "**#{event.event_type&.humanize || "General"}**",
      inline: true
    }
    fields += row1_fields

    # Add small spacing
    fields << {
      name: "\u200b",
      value: "\u200b",
      inline: false
    }

    # Row 2: Duration (inline)
    fields += [
      {
        name: "**Duration**",
        value: "**#{event.duration ? "#{event.duration} minutes" : "TBD"}**",
        inline: true
      }
    ]

    # Format scheduled time for description (on same line)
    scheduled_time_formatted = "<t:#{event.scheduled_at.to_i}:F>"
    description_text = event.description || "Join us for this event!"
    description_with_time = "**⏰ Scheduled:** #{scheduled_time_formatted}\n\n#{description_text}"

    server = event.guild&.discord_server_display_name || "Guild"
    {
      title: event.title,
      description: description_with_time,
      color: 0x5865F2, # Discord blurple
      fields: fields,
      timestamp: event.scheduled_at.iso8601,
      footer: {
        text: "GuildSync Event • #{server}"
      }
    }.tap do |embed|
      embed[:image] = { url: image_url } if image_url
    end
  end

  def create_event_signup_components(event_id)
    [
      {
        type: 1, # ACTION_ROW
        components: [
          {
            type: 2, # BUTTON
            style: 1, # PRIMARY
            label: "Sign Up",
            custom_id: "event_signup_#{event_id}",
            emoji: { name: "✅" }
          },
          {
            type: 2, # BUTTON
            style: 2, # SECONDARY
            label: "View Details",
            custom_id: "event_details_#{event_id}",
            emoji: { name: "ℹ️" }
          }
        ]
      }
    ]
  end

  def get_guild_member(guild_id, user_id)
    response = RestClient.get(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/members/#{user_id}",
      { "Authorization" => "Bot #{@bot_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    return nil if e.response.code == 404
    discord_logger.error "Discord member fetch failed: #{e.response.body}"
    raise
  end

  # Add a role to a guild member
  def add_role_to_member(guild_id, user_id, role_id)
    response = RestClient.put(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
      {},
      { "Authorization" => "Bot #{@bot_token}" }
    )
    response.code == 204
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord add role failed: #{e.response.body}"
    raise
  end

  # Remove a role from a guild member
  def remove_role_from_member(guild_id, user_id, role_id)
    response = RestClient.delete(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
      { "Authorization" => "Bot #{@bot_token}" }
    )
    response.code == 204
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord remove role failed: #{e.response.body}"
    raise
  end

  # Update member roles (replace all roles with new set)
  def update_member_roles(guild_id, user_id, role_ids)
    # Get current member to preserve existing roles we want to keep
    member = get_guild_member(guild_id, user_id)
    return false unless member

    # Get current roles
    current_roles = member["roles"] || []
    
    # Merge with new roles (avoid duplicates)
    new_roles = (current_roles + role_ids).uniq

    # Update member with new roles
    response = RestClient.patch(
      "#{DISCORD_API_BASE}/guilds/#{guild_id}/members/#{user_id}",
      { roles: new_roles }.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord update member roles failed: #{e.response.body}"
    raise
  end

  # Create a DM channel with a user
  def create_dm_channel(user_id)
    response = RestClient.post(
      "#{DISCORD_API_BASE}/users/@me/channels",
      { recipient_id: user_id }.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord DM channel creation failed: #{e.response.body}"
    raise
  end

  # Send a direct message to a user
  def send_dm(user_id, content, embed: nil, components: nil)
    dm_channel = create_dm_channel(user_id)
    send_message(dm_channel["id"], content, embed: embed, components: components)
  rescue RestClient::ExceptionWithResponse => e
    discord_logger.error "Discord DM send failed: #{e.response.body}"
    raise
  end

  # Send private message to a user (for guild applications)
  def send_private_message(discord_user_id, content)
    send_dm(discord_user_id, content)
  rescue => e
    discord_logger.error "Failed to send private message: #{e.message}"
    raise
  end
end
