require "discordrb"

# Discord Bot Service using Gateway (WebSocket) instead of HTTP interactions
# This eliminates the need for ngrok or any tunneling service
class DiscordBotService
  attr_reader :bot, :running

  def initialize
    @bot_token = ENV["DISCORD_BOT_TOKEN"]
    @discord_logger = defined?(DiscordLogger) ? DiscordLogger : Rails.logger
    @running = false
    @stop_requested = false
    @reconnect_attempts = 0
    @max_reconnect_attempts = 10
    @connection_established = false

    unless @bot_token
      @discord_logger.error "DISCORD_BOT_TOKEN not set - bot cannot start"
      return
    end

    create_bot
  end

  def create_bot
    # Use proper intents for button interactions
    # discordrb expects an array of intent symbols
    # GUILD_MEMBERS intent may be needed for some interactions
    intents = [
      :servers,
      :server_messages,
      :server_message_reactions,
      :server_members # May be needed for button interactions in some cases
    ]

    begin
      @discord_logger.info "Creating Discord bot with token: #{@bot_token[0..10]}..." if @bot_token
      @discord_logger.info "Intents: #{intents.inspect}"

      # Fix SSL certificate verification issue on macOS
      # Set SSL_CERT_FILE environment variable so WebSocket library can find certificates
      if RUBY_PLATFORM.include?("darwin")
        cert_paths = [
          "/opt/homebrew/etc/openssl@3/cert.pem",
          "/usr/local/etc/openssl@3/cert.pem",
          "/usr/local/etc/openssl/cert.pem",
          "/opt/homebrew/etc/openssl/cert.pem",
          "/etc/ssl/cert.pem",
          "/etc/ssl/certs/ca-certificates.crt"
        ]

        cert_path = cert_paths.find { |path| File.exist?(path) }
        if cert_path
          @discord_logger.info "Setting SSL_CERT_FILE to: #{cert_path}"
          ENV["SSL_CERT_FILE"] = cert_path
        else
          @discord_logger.warn "No system certificate file found - SSL verification may fail"
        end
      end

      # Enable debug mode to see connection issues
      @bot = Discordrb::Bot.new(
        token: @bot_token,
        intents: intents,
        log_mode: :debug # Enable debug to see WebSocket connection details
      )

      @discord_logger.info "Discord bot object created successfully"
      setup_event_handlers
      @discord_logger.info "Event handlers set up"

      # Verify bot token is valid by checking profile
      begin
        profile = @bot.profile
        @discord_logger.info "Bot profile verified: #{profile.username} (ID: #{profile.id})"
      rescue => e
        @discord_logger.error "Failed to verify bot profile - token may be invalid: #{e.message}"
        raise "Invalid bot token or token verification failed"
      end
    rescue => e
      @discord_logger.error "Failed to create Discord bot: #{e.class.name}: #{e.message}"
      @discord_logger.error e.backtrace.first(10).join("\n")
      raise
    end
  end

  def start
    return unless @bot
    return if @running

    @running = true
    @stop_requested = false
    @reconnect_attempts = 0

    # Start bot in background thread - run() is blocking, so it needs its own thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        run_with_auto_reconnect
      end
    end

    # Start health check monitor
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        monitor_bot_health
      end
    end
  end

  def run_with_auto_reconnect
    loop do
      break if @stop_requested

      begin
        @discord_logger.info "Starting Discord bot connection (attempt #{@reconnect_attempts + 1})..."

        # Reset connection flag - ready event will set this to true
        @connection_established = false
        @bot_error = nil

        # run(false) is blocking - it will block until bot disconnects
        # We run it in a thread so it doesn't block the main thread
        # The ready event will fire when connection is established
        bot_thread = Thread.new do
          begin
            @discord_logger.info "Calling @bot.run(false) - starting WebSocket connection (blocking)..."
            @discord_logger.info "Bot token present: #{@bot_token.present?}"
            @discord_logger.info "Bot object: #{@bot.inspect[0..100]}..."

            # Use blocking mode - this will establish the connection and wait for ready event
            # This should connect to Discord Gateway and fire ready event
            @bot.run(false) # Blocking mode - waits for connection, ready event fires when connected
            @discord_logger.info "@bot.run() returned (bot disconnected)"
          rescue => e
            @bot_error = e
            @discord_logger.error "========================================"
            @discord_logger.error "CRITICAL: Error in bot.run thread!"
            @discord_logger.error "Error class: #{e.class.name}"
            @discord_logger.error "Error message: #{e.message}"
            @discord_logger.error "Full error: #{e.inspect}"
            @discord_logger.error "Backtrace:"
            @discord_logger.error e.backtrace.first(20).join("\n")
            @discord_logger.error "========================================"
          end
        end

        # Wait for ready event to fire (which sets @connection_established = true)
        # Give it up to 15 seconds to connect
        connection_timeout = 15
        waited = 0
        @discord_logger.info "Waiting for bot ready event (timeout: #{connection_timeout}s)..."

        while waited < connection_timeout && !@connection_established && !@stop_requested
          sleep(1)
          waited += 1

          # Check for errors in bot thread
          if @bot_error
            @discord_logger.error "Bot connection error detected: #{@bot_error.class.name}: #{@bot_error.message}"
            bot_thread.kill if bot_thread.alive?
            raise "Bot failed to connect: #{@bot_error.message}"
          end

          # Check if bot thread died unexpectedly
          if bot_thread.status == false
            @discord_logger.error "Bot thread died unexpectedly"
            raise "Bot thread terminated unexpectedly"
          end
        end

        if @connection_established
          @discord_logger.info "Bot connection established successfully via ready event!"
          # Monitor connection status - wait for disconnect
          loop do
            sleep(5)
            break if @stop_requested || bot_thread.status == false

            # Check if bot is still connected (if method is available)
            if @bot.respond_to?(:connected?) && @bot.connected? == false
              @discord_logger.warn "Bot connection lost (connected? returned false)"
              break
            end
          end
        else
          @discord_logger.error "Bot failed to connect after #{connection_timeout} seconds"
          @discord_logger.error "Bot thread status: #{bot_thread.status.inspect}"
          @discord_logger.error "Connection established flag: #{@connection_established.inspect}"

          if @bot_error
            @discord_logger.error "Bot connection error occurred: #{@bot_error.class.name}: #{@bot_error.message}"
            bot_thread.kill if bot_thread.alive?
            raise "Bot failed to connect: #{@bot_error.message}"
          end

          # Try to get more info about why it failed
          begin
            if @bot.respond_to?(:profile)
              @discord_logger.error "Bot profile accessible: #{@bot.profile.username rescue 'error'}"
            end
          rescue => e
            @discord_logger.error "Could not get bot profile: #{e.message}"
          end

          bot_thread.kill if bot_thread.alive?
          raise "Bot failed to establish connection - ready event did not fire within #{connection_timeout} seconds"
        end

        # If we get here, bot disconnected
        if @stop_requested
          @discord_logger.info "Bot stop requested - not reconnecting"
          bot_thread.kill if bot_thread.alive?
          break
        end

        @discord_logger.warn "Discord bot disconnected unexpectedly"
        bot_thread.kill if bot_thread.alive?

      rescue => e
        @discord_logger.error "Discord bot error: #{e.class.name}: #{e.message}"
        @discord_logger.error e.backtrace.first(10).join("\n")
      end

      # Auto-reconnect with exponential backoff
      unless @stop_requested
        @reconnect_attempts += 1

        if @reconnect_attempts > @max_reconnect_attempts
          @discord_logger.error "Max reconnection attempts (#{@max_reconnect_attempts}) reached. Health monitor will take over."
          # Don't break - let health monitor handle it
          sleep(60) # Wait longer before next attempt
          @reconnect_attempts = 0 # Reset for health monitor
          next
        end

        # Exponential backoff: 5s, 10s, 20s, 40s, 60s (max)
        wait_time = [ 5 * (2 ** (@reconnect_attempts - 1)), 60 ].min
        @discord_logger.info "Reconnecting in #{wait_time} seconds... (attempt #{@reconnect_attempts}/#{@max_reconnect_attempts})"

        sleep(wait_time)

        # Recreate bot if needed (only if not connected)
        unless @bot&.connected?
          @discord_logger.info "Recreating bot connection..."
          begin
            @bot.stop if @bot.connected?
          rescue => e
            @discord_logger.warn "Error stopping old bot: #{e.message}"
          end
          create_bot
        end
      end
    end

    @running = false
    @discord_logger.info "Discord bot auto-reconnect loop ended"
  end

  def monitor_bot_health
    loop do
      break if @stop_requested

      sleep(30) # Check every 30 seconds

      # Use our connected? method which checks both flags
      if @running && @bot && !connected? && !@stop_requested
        @discord_logger.warn "Bot health check: Bot is not connected! (connection_established=#{@connection_established}, bot.connected?=#{@bot.connected?.inspect})"

        # Only intervene if bot has been disconnected for a while
        # Don't interfere with active reconnection attempts
        if @reconnect_attempts < 3
          @discord_logger.info "Reconnection in progress (attempt #{@reconnect_attempts}) - health monitor waiting..."
          next
        end

        # Force reconnection
        begin
          @bot.stop if @bot.respond_to?(:connected?) && @bot.connected?
        rescue => e
          @discord_logger.warn "Error stopping bot during health check: #{e.message}"
        end

        # Reset connection flag
        @connection_established = false

        # Recreate bot and restart
        @discord_logger.info "Health monitor: Recreating bot connection..."
        create_bot

        # Reset reconnect attempts to allow reconnection
        @reconnect_attempts = 0

        # Give it a moment to start
        sleep(2)
      end
    end
  end

  def stop
    @stop_requested = true
    @running = false

    return unless @bot

    begin
      @bot.stop if @bot.connected?
    rescue => e
      @discord_logger.warn "Error stopping bot: #{e.message}"
    end

    @discord_logger.info "Discord bot stopped"
  end

  def connected?
    # Check both the ready event flag and the bot's connected? method
    # @connection_established is set by the ready event
    # @bot.connected? may return nil before connection, true when connected, false when disconnected
    @connection_established == true || (@bot&.connected? == true)
  end

  def ensure_running
    return if @running && connected?

    if !@running
      @discord_logger.info "Bot not running - starting..."
      start
    elsif @running && !connected?
      @discord_logger.warn "Bot running but not connected - will reconnect automatically"
    end
  end

  private

  def setup_event_handlers
    return unless @bot

    # =========================================================================
    # Slash command (application command) handlers
    # discordrb routes INTERACTION_CREATE type:2 events by command name.
    # For subcommand groups, .subcommand(name) must be called on the handler
    # returned by application_command — otherwise discordrb silently drops
    # the event without calling any block.
    # =========================================================================
    setup_application_command_handlers

    # Handle button click interactions (discordrb uses button method with custom_id pattern)
    @bot.button(custom_id: /^event_signup_/) do |event|
      handle_button_interaction(event)
    end

    # Handle status selection buttons
    @bot.button(custom_id: /^event_status_/) do |event|
      handle_status_selection(event)
    end

    # Handle alliance RSVP buttons
    @bot.button(custom_id: /^alliance_event_(signup|status)_/) do |event|
      handle_button_interaction(event)
    end

    # Handle poll vote buttons
    @bot.button(custom_id: /^poll_vote_/) do |event|
      handle_poll_vote_interaction(event)
    end

    @bot.button(custom_id: /^alliance_poll_vote_/) do |event|
      handle_alliance_poll_vote_interaction(event)
    end

    # Handle loot roll buttons
    @bot.button(custom_id: /^loot_roll_/) do |event|
      handle_loot_roll_interaction(event)
    end

    @bot.button(custom_id: /^alliance_loot_roll_/) do |event|
      handle_alliance_loot_roll_interaction(event)
    end

    # Handle react role reactions: add and remove
    @bot.reaction_add do |event|
      next unless event.user && event.emoji
      next if event.user.id == @bot.profile.id  # ignore bot's own seeded reactions

      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          handle_react_role_event(event, :add)
        end
      end
    end

    @bot.reaction_remove do |event|
      next unless event.user && event.emoji
      next if event.user.id == @bot.profile.id

      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          handle_react_role_event(event, :remove)
        end
      end
    end

    # Handle ready event - this fires when bot successfully connects to Discord Gateway
    @bot.ready do |event|
      begin
        @reconnect_attempts = 0 # Reset on successful connection
        @connection_established = true
        @discord_logger.info "========================================"
        @discord_logger.info "🎉 Discord bot ready! Logged in as #{event.bot.profile.username} (ID: #{event.bot.profile.id})"
        @discord_logger.info "Bot is online and ready to handle slash commands and button interactions!"
        @discord_logger.info "WebSocket connection established successfully!"
        @discord_logger.info "========================================"
      rescue => e
        @discord_logger.error "Error in ready event handler: #{e.class.name}: #{e.message}"
        @discord_logger.error e.backtrace.first(10).join("\n")
      end
    end

    # Handle images in Members Gear channel (optional - for auto-detection)
    # This allows images posted in gear channels to be automatically processed
    @bot.message do |event|
      # Validate event structure
      next unless event.message && event.message.attachments
      next unless event.message.attachments.any? { |a| a.image? }
      next unless event.server && event.channel

      # Check if this channel is configured as a gear channel for any guild
      channel_id = event.channel.id.to_s
      guild_discord_id = event.server.id.to_s

      guild_setting = GuildDiscordSetting.find_by(
        discord_guild_id: guild_discord_id,
        gear_channel_id: channel_id
      )

      if guild_setting && guild_setting.guild
        # Process image upload automatically
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            begin
              DiscordGearService.handle_channel_image_message(event, guild_setting.guild)
            rescue => e
              @discord_logger.error "Auto gear upload error: #{e.message}"
              @discord_logger.error e.backtrace.first(5).join("\n")
            end
          end
        end
      end
    end
  end

  # =========================================================================
  # Application command (slash command) routing
  # =========================================================================

  COMMANDS_WITH_SUBCOMMANDS = {
    event:       [:create, :list, :view, :cancel],
    poll:        [:create, :list, :results],
    loot:        [:create, :list, :view, :close],
    member:      [:list, :info, :kick, :role],
    guild:       [:info, :settings, :channels],
    application: [:list, :view, :accept, :reject],
    docs:        [:list, :view, :search],
    profile:     [:me, :view],
    gear:        [:upload, :my, :request, :request_missing],
    alliance:    [:info, :hub, :requests]
  }.freeze

  TOP_LEVEL_COMMANDS = [:invite, :leaderboard, :activity, :help, :signup].freeze

  def setup_application_command_handlers
    # Commands that have subcommands must chain .subcommand(name) explicitly.
    # Without it, discordrb calls the main block only when there is NO subcommand,
    # and silently returns for unhandled subcommands.

    COMMANDS_WITH_SUBCOMMANDS.each do |cmd_name, subcommands|
      handler = @bot.application_command(cmd_name)
      subcommands.each do |sub_name|
        handler.subcommand(sub_name) do |e|
          if cmd_name == :gear
            dispatch_gear_command(e)
          else
            dispatch_application_command(e)
          end
        end
      end
    end

    TOP_LEVEL_COMMANDS.each do |cmd_name|
      @bot.application_command(cmd_name) do |e|
        case cmd_name
        when :signup then dispatch_signup_command(e)
        else dispatch_application_command(e)
        end
      end
    end
  end

  # Main dispatcher: builds interaction hash → calls service → responds.
  def dispatch_application_command(event)
    cmd = event.command_name.to_s
    sub = event.subcommand ? " #{event.subcommand}" : ""
    @discord_logger.info "[Bot] /#{cmd}#{sub} from #{event.user.username} (#{event.user.id})"

    interaction = build_gateway_interaction(event)

    service_map = {
      "poll"        => DiscordPollCommandService,
      "loot"        => DiscordLootCommandService,
      "event"       => DiscordEventCommandService,
      "invite"      => DiscordInviteCommandService,
      "member"      => DiscordMemberCommandService,
      "guild"       => DiscordGuildCommandService,
      "application" => DiscordApplicationCommandService,
      "docs"        => DiscordDocsCommandService,
      "leaderboard" => DiscordLeaderboardCommandService,
      "activity"    => DiscordActivityCommandService,
      "profile"     => DiscordProfileCommandService,
      "alliance"    => DiscordAllianceCommandService,
      "help"        => DiscordHelpCommandService
    }

    service_class = service_map[cmd]
    unless service_class
      event.respond(content: "Unknown command /#{cmd}", ephemeral: true)
      return
    end

    result = service_class.handle(interaction)
    respond_to_gateway_interaction(event, result)
  rescue => e
    @discord_logger.error "[Bot] /#{cmd}#{sub} error: #{e.class}: #{e.message}"
    @discord_logger.error e.backtrace.first(5).join("\n")
    begin
      event.respond(content: "An error occurred processing your command. Please try again.", ephemeral: true)
    rescue => re
      @discord_logger.error "Could not send error response: #{re.message}"
    end
  end

  # Gear command dispatcher — upload needs deferred+thread, others are synchronous.
  def dispatch_gear_command(event)
    @discord_logger.info "[Bot] /gear #{event.subcommand} from #{event.user.username}"

    interaction = build_gateway_interaction(event)
    token = event.interaction.token

    case event.subcommand
    when :upload
      event.defer(ephemeral: true)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            result = DiscordGearService.handle_upload_command(interaction)
            content = result&.dig(:data, :content)
            ephemeral = (result&.dig(:data, :flags).to_i & 64) == 64
            send_followup_via_webhook_with_token(token, content || "Upload processed.", ephemeral: ephemeral)
          rescue => e
            @discord_logger.error "Gear upload error: #{e.message}"
            send_followup_via_webhook_with_token(token, "An error occurred processing your upload.", ephemeral: true)
          end
        end
      end
    when :my
      respond_to_gateway_interaction(event, DiscordGearService.handle_my_command(interaction))
    when :request
      respond_to_gateway_interaction(event, DiscordGearService.handle_request_command(interaction))
    when :request_missing
      respond_to_gateway_interaction(event, DiscordGearService.handle_request_missing_command(interaction))
    else
      event.respond(content: "Unknown gear subcommand.", ephemeral: true)
    end
  rescue => e
    @discord_logger.error "Gear command error: #{e.class}: #{e.message}"
    begin
      event.respond(content: "An error occurred.", ephemeral: true)
    rescue; end
  end

  # Signup command dispatcher — shows role→attendance selection flow.
  def dispatch_signup_command(event)
    @discord_logger.info "[Bot] /signup from #{event.user.username}"

    interaction = build_gateway_interaction(event)
    options = interaction.dig("data", "options") || []

    role_option = options.find { |o| o["name"] == "role" }
    unless role_option
      event.respond(content: "Usage: /signup role:<dps|tank|healer|ranged> event:<event_id>", ephemeral: true)
      return
    end

    role = role_option["value"]
    event_id = options.find { |o| o["name"] == "event" }&.dig("value")&.to_i

    # If event_id is missing, check if this was used in reply to a message
    if event_id.nil? || event_id <= 0
      message_id = event.interaction.data.dig("message", "id")
      if message_id
        de = DiscordEvent.find_by(discord_message_id: message_id)
        event_id = de&.id
      end
    end

    unless event_id&.positive?
      event.respond(
        content: "Please provide an event ID or use this command in reply to an event message. Use /event list to see available events.",
        ephemeral: true
      )
      return
    end

    interaction_token = event.interaction.token
    discord_user_id   = event.user.id.to_s

    event.defer(ephemeral: true)

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          de = DiscordEvent.find_by(id: event_id)
          unless de
            send_followup_via_webhook_with_token(interaction_token, "Event not found. Use /event list.", ephemeral: true)
            next
          end
          show_attendance_selection_gateway_with_token(interaction_token, de, role, discord_user_id)
        rescue => e
          @discord_logger.error "Signup command error: #{e.message}"
          send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
        end
      end
    end
  rescue => e
    @discord_logger.error "Signup dispatch error: #{e.class}: #{e.message}"
    begin
      event.respond(content: "An error occurred.", ephemeral: true)
    rescue; end
  end

  # Builds the interaction hash our service classes expect from a discordrb ApplicationCommandEvent.
  def build_gateway_interaction(event)
    user = event.user

    # discordrb pre-processes options into { "name" => value } — rebuild the Discord array format
    flat_options = (event.options || {}).map { |name, value| { "name" => name.to_s, "value" => value } }

    # Wrap in subcommand structure when applicable
    data_options = if event.subcommand
      [{ "type" => 1, "name" => event.subcommand.to_s, "options" => flat_options }]
    else
      flat_options
    end

    {
      "guild_id" => event.server_id.to_s,
      "token"    => event.interaction.token,
      "member"   => {
        "user" => {
          "id"       => user.id.to_s,
          "username" => user.username
        }
      },
      "data" => {
        "name"     => event.command_name.to_s,
        "options"  => data_options,
        "resolved" => event.interaction.data["resolved"] || {}
      }
    }
  end

  # Translates a service response hash into a discordrb interaction response.
  def respond_to_gateway_interaction(event, result)
    return unless result.is_a?(Hash)

    type       = result[:type]       || result["type"]
    data       = result[:data]       || result["data"] || {}
    flags      = (data[:flags]       || data["flags"] || 0).to_i
    content    = data[:content]      || data["content"]
    embeds     = data[:embeds]       || data["embeds"]
    components = data[:components]   || data["components"]
    ephemeral  = (flags & 64) == 64

    case type
    when 4  # CHANNEL_MESSAGE_WITH_SOURCE
      opts = { ephemeral: ephemeral }
      opts[:content]    = content    if content.present?
      opts[:embeds]     = embeds     if embeds.present?
      opts[:components] = components if components.present?
      event.respond(**opts)
    when 5  # DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE (DiscordCommandJob sends follow-up)
      event.defer(ephemeral: ephemeral)
    end
  rescue => e
    @discord_logger.error "[Bot] respond_to_gateway_interaction error: #{e.class}: #{e.message}"
  end

  def handle_button_interaction(event)
    # Log immediately to verify interactions are being received
    @discord_logger.info "========================================"
    @discord_logger.info "BUTTON INTERACTION RECEIVED (Gateway)"
    @discord_logger.info "Custom ID: #{event.custom_id}"
    @discord_logger.info "User: #{event.user.username}##{event.user.discriminator} (ID: #{event.user.id})"
    @discord_logger.info "Channel: #{event.channel.id}"
    @discord_logger.info "========================================"

    custom_id = event.custom_id

    unless custom_id
      @discord_logger.error "No custom_id in button interaction"
      begin
        event.respond(content: "Invalid button interaction", ephemeral: true)
      rescue => e
        @discord_logger.error "Failed to respond: #{e.message}"
      end
      return
    end

    if custom_id.start_with?("event_signup_")
      parts = custom_id.split("_")
      if parts.length >= 4
        event_id = parts[2].to_i
        role = parts[3]
        @discord_logger.info "Processing signup: event_id=#{event_id}, role=#{role}"

        handle_event_signup_via_gateway(event, event_id, role)
      else
        @discord_logger.warn "Invalid event_signup format: #{custom_id} (parts: #{parts.inspect})"
        begin
          event.respond(content: "Invalid button format", ephemeral: true)
        rescue => e
          @discord_logger.error "Failed to respond: #{e.message}"
        end
      end
    elsif custom_id.start_with?("alliance_event_signup_")
      parts = custom_id.split("_")
      if parts.length >= 5
        alliance_event_id = parts[3].to_i
        role = parts[4]
        handle_alliance_event_signup_via_gateway(event, alliance_event_id, role)
      else
        begin
          event.respond(content: "Invalid alliance signup format", ephemeral: true)
        rescue => e
          @discord_logger.error "Failed to respond: #{e.message}"
        end
      end
    elsif custom_id.start_with?("alliance_event_status_")
      parts = custom_id.split("_")
      if parts.length >= 7
        alliance_event_id = parts[3].to_i
        role = parts[4]
        status = parts[5..-2].join("_")
        user_id = parts[-1]
        handle_alliance_event_status_via_gateway(event, alliance_event_id, role, status, user_id)
      else
        begin
          event.respond(content: "Invalid alliance status format", ephemeral: true)
        rescue => e
          @discord_logger.error "Failed to respond: #{e.message}"
        end
      end
    else
      @discord_logger.warn "Unknown custom_id: #{custom_id}"
      begin
        event.respond(content: "Unknown interaction", ephemeral: true)
      rescue => e
        @discord_logger.error "Failed to respond: #{e.message}"
      end
    end
  rescue => e
    @discord_logger.error "Error handling button interaction: #{e.class.name}: #{e.message}"
    @discord_logger.error e.backtrace.first(10).join("\n")
    begin
      event.respond(content: "An error occurred. Please try again.", ephemeral: true)
    rescue => response_error
      @discord_logger.error "Failed to send error response: #{response_error.message}"
    end
  end

  def handle_event_signup_via_gateway(button_event, event_id, role)
    # CRITICAL: Store token BEFORE deferring (token might not be accessible after)
    interaction_token = nil
    if button_event.respond_to?(:token) && button_event.token.present?
      interaction_token = button_event.token
    elsif button_event.respond_to?(:interaction) && button_event.interaction.respond_to?(:token) && button_event.interaction.token.present?
      interaction_token = button_event.interaction.token
    end

    @discord_logger.info "Stored interaction token: #{interaction_token[0..20] if interaction_token}..."

    # CRITICAL: Defer response IMMEDIATELY - must be first thing we do
    begin
      button_event.defer_update
      @discord_logger.info "Deferred update sent to Discord for event_id=#{event_id}, role=#{role}"
    rescue => e
      @discord_logger.error "Failed to defer update: #{e.message}"
      begin
        button_event.respond(content: "Processing...", ephemeral: true)
      rescue => e2
        @discord_logger.error "Failed to send any response: #{e2.message}"
      end
      return
    end

    # Process in background thread to avoid blocking
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          # Find the DiscordEvent in our database
          discord_event_record = DiscordEvent.find_by(id: event_id)

          unless discord_event_record
            @discord_logger.error "DiscordEvent not found for id=#{event_id}"
            send_followup_via_webhook_with_token(interaction_token, "Event not found", ephemeral: true)
            next
          end

          unless DiscordEvent::ROLE_CATEGORIES.include?(role)
            @discord_logger.error "Invalid role: #{role}. Valid roles: #{DiscordEvent::ROLE_CATEGORIES.inspect}"
            send_followup_via_webhook_with_token(interaction_token, "Invalid role", ephemeral: true)
            next
          end

          discord_user_id = button_event.user.id.to_s
          discord_username = gateway_discord_login(button_event.user)

          # Get display name (server nickname) from Discord member
          discord_display_name = nil
          begin
            guild_id = discord_event_record.guild.discord_id || discord_event_record.guild.guild_discord_setting&.discord_guild_id
            if guild_id
              bot_token = ENV["DISCORD_BOT_TOKEN"]
              service = DiscordService.new(bot_token: bot_token)
              member = service.get_guild_member(guild_id, discord_user_id)
              discord_display_name = DiscordGuildMemberLabel.from_member_json(member) if member
            end
          rescue => e
            @discord_logger.warn "Could not fetch Discord member display name: #{e.message}"
          end
          discord_display_name ||= gateway_interaction_member_display_name(button_event)
          discord_display_name ||= gateway_discord_user_display_name(button_event.user)
          discord_display_name ||= discord_username

          @discord_logger.info "Processing signup for user: #{discord_username} (#{discord_user_id}), display name: #{discord_display_name}"

          # ALWAYS show attendance selection, even if user already has a signup
          # DO NOT save yet - we'll save when attendance is chosen
          # This allows users to change their role and attendance status anytime
          if interaction_token.present?
            show_attendance_selection_gateway_with_token(interaction_token, discord_event_record, role, discord_user_id)
          else
            @discord_logger.error "Cannot show attendance selection: interaction_token is missing"
          end
        rescue => e
          @discord_logger.error "Event signup error: #{e.class.name}: #{e.message}"
          @discord_logger.error e.backtrace.first(10).join("\n")
          send_followup_via_webhook(button_event, "An error occurred. Please try again.")
        end
      end
    end
  end

  def handle_alliance_event_signup_via_gateway(button_event, alliance_event_id, role)
    interaction_token = nil
    if button_event.respond_to?(:token) && button_event.token.present?
      interaction_token = button_event.token
    elsif button_event.respond_to?(:interaction) && button_event.interaction.respond_to?(:token) && button_event.interaction.token.present?
      interaction_token = button_event.interaction.token
    end

    begin
      button_event.defer_update
    rescue => e
      @discord_logger.error "Failed to defer alliance RSVP update: #{e.message}"
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          event = AllianceEvent.find_by(id: alliance_event_id)
          if event.blank? || !event.role_categories_for_discord.include?(role)
            send_followup_via_webhook_with_token(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.event_not_found"), ephemeral: true)
            next
          end

          discord_user_id = button_event.user.id.to_s
          components = AllianceDiscordBroadcastService.attendance_buttons_for(event.id, role, discord_user_id)
          send_followup_via_webhook_with_token(
            interaction_token,
            "You selected **#{role.upcase}**. How will you be attending?",
            components: components,
            ephemeral: true
          )
        rescue => e
          @discord_logger.error "Alliance signup gateway error: #{e.class.name}: #{e.message}"
          send_followup_via_webhook_with_token(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.unexpected"), ephemeral: true)
        end
      end
    end
  end

  def handle_alliance_event_status_via_gateway(button_event, alliance_event_id, role, status, user_id)
    interaction_token = nil
    if button_event.respond_to?(:token) && button_event.token.present?
      interaction_token = button_event.token
    elsif button_event.respond_to?(:interaction) && button_event.interaction.respond_to?(:token) && button_event.interaction.token.present?
      interaction_token = button_event.interaction.token
    end

    begin
      button_event.defer_update
    rescue => e
      @discord_logger.error "Failed to defer alliance status update: #{e.message}"
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          discord_user_id = button_event.user.id.to_s
          if discord_user_id != user_id.to_s
            send_followup_via_webhook_with_token(interaction_token, "This status button is not for your account.", ephemeral: true)
            next
          end

          handler = UnregisteredInteractionHandler.new(discord_user_id: discord_user_id)
          resolved_user = handler.resolve_user

          discord_login = gateway_discord_login(button_event.user)
          display_name = gateway_interaction_member_display_name(button_event)
          server_id = button_event.respond_to?(:server) && button_event.server ? button_event.server.id.to_s : nil
          if display_name.blank? && server_id.present? && resolved_user
            g = DiscordGuildMemberLabel.guild_from_discord_snowflake(server_id)
            if g
              display_name = DiscordGuildMemberLabel.for_user_in_guild(user: resolved_user, guild: g, cache: {})
            end
          end
          display_name ||= gateway_discord_user_display_name(button_event.user)

          result = AllianceDiscordBroadcastService.apply_status_selection(
            event_id: alliance_event_id,
            role: role,
            status: status,
            discord_user_id: discord_user_id,
            discord_username: discord_login,
            discord_display_name: display_name
          )

          if result[:ok]
            send_followup_via_webhook_with_token(interaction_token, "✅ Alliance event status updated: **#{role.upcase}** - **#{status.humanize}**", ephemeral: true)
          else
            message = case result[:error]
            when :link_required then I18n.t("alliances.events.discord_rsvp.errors.link_required")
            when :event_not_found then I18n.t("alliances.events.discord_rsvp.errors.event_not_found")
            when :invalid_status then I18n.t("alliances.events.discord_rsvp.errors.invalid_status")
            when :not_alliance_member then I18n.t("alliances.events.discord_rsvp.errors.not_alliance_member")
            when :save_failed then I18n.t("alliances.events.discord_rsvp.errors.save_failed", error: result[:message])
            else I18n.t("alliances.events.discord_rsvp.errors.unexpected")
            end
            send_followup_via_webhook_with_token(interaction_token, message, ephemeral: true)
          end
        rescue => e
          @discord_logger.error "Alliance status gateway error: #{e.class.name}: #{e.message}"
          send_followup_via_webhook_with_token(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.unexpected"), ephemeral: true)
        end
      end
    end
  end

  def send_followup_via_webhook(button_event, content, components: nil, ephemeral: false)
    # Try multiple ways to get the interaction token
    interaction_token = nil
    application_id = ENV["DISCORD_CLIENT_ID"]

    # Method 1: button_event.token (most common in discordrb)
    if button_event.respond_to?(:token) && button_event.token.present?
      interaction_token = button_event.token
      @discord_logger.info "Got token via button_event.token"
    # Method 2: button_event.interaction.token
    elsif button_event.respond_to?(:interaction) && button_event.interaction.respond_to?(:token) && button_event.interaction.token.present?
      interaction_token = button_event.interaction.token
      @discord_logger.info "Got token via button_event.interaction.token"
    else
      @discord_logger.error "Cannot send followup: button_event missing token"
      @discord_logger.error "Button event class: #{button_event.class}"
      @discord_logger.error "Available methods with 'token': #{button_event.methods.grep(/token/).inspect}"
      @discord_logger.error "Available methods with 'interaction': #{button_event.methods.grep(/interaction/).inspect}"
      return
    end

    send_followup_via_webhook_with_token(interaction_token, content, components: components, ephemeral: ephemeral)
  end

  def show_attendance_selection_gateway_with_token(interaction_token, discord_event, role, user_id)
    # Create attendance status selection buttons (removed tentative)
    components = [ {
      type: 1,
      components: [
        {
          type: 2,
          style: 1, # Primary (blue)
          label: "✅ On Time",
          custom_id: "event_status_#{discord_event.id}_#{role}_on_time_#{user_id}"
        },
        {
          type: 2,
          style: 2, # Secondary (gray)
          label: "⏰ Late",
          custom_id: "event_status_#{discord_event.id}_#{role}_late_#{user_id}"
        },
        {
          type: 2,
          style: 4, # Danger (red)
          label: "❌ Absent",
          custom_id: "event_status_#{discord_event.id}_#{role}_absent_#{user_id}"
        },
        {
          type: 2,
          style: 4, # Danger (red)
          label: "Remove",
          custom_id: "event_status_#{discord_event.id}_#{role}_remove_#{user_id}"
        }
      ]
    } ]

    # After defer_update, use webhook followup with stored token
    # Make it ephemeral so only the user sees it
    send_followup_via_webhook_with_token(
      interaction_token,
      "You selected **#{role.upcase}**. How will you be attending?",
      components: components,
      ephemeral: true
    )
  end

  def send_followup_via_webhook_with_token(interaction_token, content, components: nil, ephemeral: false)
    unless interaction_token.present?
      @discord_logger.error "Cannot send followup: interaction_token is missing"
      return
    end

    begin
      bot_token = ENV["DISCORD_BOT_TOKEN"]
      application_id = ENV["DISCORD_CLIENT_ID"]

      @discord_logger.info "Sending followup message with token: #{interaction_token[0..20]}..., application_id: #{application_id}"

      payload = { content: content }
      payload[:flags] = 64 if ephemeral # flags: 64 = EPHEMERAL (private to user)
      payload[:components] = components if components.present?

      response = RestClient.post(
        "https://discord.com/api/v10/webhooks/#{application_id}/#{interaction_token}",
        payload.to_json,
        {
          "Authorization" => "Bot #{bot_token}",
          "Content-Type" => "application/json"
        }
      )

      @discord_logger.info "Followup message sent successfully: #{response.code}"
    rescue RestClient::ExceptionWithResponse => e
      @discord_logger.error "Failed to send follow-up message: #{e.response.code} - #{e.response.body}"
      @discord_logger.error "Token: #{interaction_token[0..20]}..., Application ID: #{application_id}"
    rescue => e
      @discord_logger.error "Failed to send follow-up message: #{e.class.name}: #{e.message}"
      @discord_logger.error e.backtrace.first(5).join("\n")
    end
  end

  def handle_poll_vote_interaction(event)
    # Log immediately to verify interactions are being received
    @discord_logger.info "========================================"
    @discord_logger.info "POLL VOTE INTERACTION RECEIVED (Gateway)"
    @discord_logger.info "Custom ID: #{event.custom_id}"
    @discord_logger.info "User: #{event.user.username}##{event.user.discriminator} (ID: #{event.user.id})"
    @discord_logger.info "Channel: #{event.channel.id}"
    @discord_logger.info "========================================"

    # CRITICAL: Store token BEFORE deferring
    interaction_token = nil
    if event.respond_to?(:token) && event.token.present?
      interaction_token = event.token
    elsif event.respond_to?(:interaction) && event.interaction.respond_to?(:token) && event.interaction.token.present?
      interaction_token = event.interaction.token
    end

    # CRITICAL: Defer response IMMEDIATELY
    begin
      event.defer_update
      @discord_logger.info "Deferred update sent for poll vote"
    rescue => e
      @discord_logger.error "Failed to defer poll vote update: #{e.message}"
      return
    end

    custom_id = event.custom_id
    # Format: poll_vote_{poll_id}_{choice}
    parts = custom_id.split("_")

    unless parts.length >= 4
      @discord_logger.error "Invalid poll_vote format: #{custom_id}"
      send_followup_via_webhook_with_token(interaction_token, "Invalid vote format", ephemeral: true)
      return
    end

    poll_id = parts[2].to_i
    choice_str = parts[3] # "yes", "no", or "maybe"

    # Map choice string to enum value
    choice_map = { "yes" => 0, "no" => 1, "maybe" => 2 }
    choice = choice_map[choice_str]

    unless choice
      @discord_logger.error "Invalid poll choice: #{choice_str}"
      send_followup_via_webhook_with_token(interaction_token, "Invalid vote choice", ephemeral: true)
      return
    end

    discord_user_id = event.user.id.to_s

    # Process in background thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          poll = Poll.find_by(id: poll_id)
          unless poll
            send_followup_via_webhook_with_token(interaction_token, "Poll not found", ephemeral: true)
            next
          end

          unless poll.open?
            send_followup_via_webhook_with_token(interaction_token, "This poll is closed", ephemeral: true)
            next
          end

          # Find user by Discord ID - check UserDiscordConnection
          user_discord_connection = UserDiscordConnection.find_by(discord_user_id: discord_user_id)
          unless user_discord_connection
            send_followup_via_webhook_with_token(interaction_token, "Please connect your Discord account to GuildSync to vote", ephemeral: true)
            next
          end

          user = user_discord_connection.user

          # Verify user is a member of the guild
          unless poll.guild.members.include?(user) || poll.guild.owner == user
            send_followup_via_webhook_with_token(interaction_token, "You must be a member of this guild to vote", ephemeral: true)
            next
          end

          # Find or create vote
          vote = poll.poll_votes.find_or_initialize_by(user: user)
          vote.choice = choice

          if vote.save
            # Update Discord message with new counts
            DiscordPollService.new(poll).update_poll_message

            choice_labels = { 0 => "✅ Yes", 1 => "❌ No", 2 => "🤔 Maybe" }
            send_followup_via_webhook_with_token(interaction_token, "Vote recorded: #{choice_labels[choice]}", ephemeral: true)
            @discord_logger.info "Poll vote saved - poll_id: #{poll_id}, user: #{user.display_name}, choice: #{choice_str}"
          else
            send_followup_via_webhook_with_token(interaction_token, "Failed to save vote: #{vote.errors.full_messages.join(', ')}", ephemeral: true)
          end
        rescue => e
          @discord_logger.error "Poll vote error: #{e.class.name}: #{e.message}"
          @discord_logger.error e.backtrace.first(10).join("\n")
          send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
        end
      end
    end
  rescue => e
    @discord_logger.error "Poll vote interaction error: #{e.class.name}: #{e.message}"
    @discord_logger.error e.backtrace.first(10).join("\n")
  end

  def handle_loot_roll_interaction(event)
    # Log immediately to verify interactions are being received
    @discord_logger.info "========================================"
    @discord_logger.info "LOOT ROLL INTERACTION RECEIVED (Gateway)"
    @discord_logger.info "Custom ID: #{event.custom_id}"
    @discord_logger.info "User: #{event.user.username}##{event.user.discriminator} (ID: #{event.user.id})"
    @discord_logger.info "Channel: #{event.channel.id}"
    @discord_logger.info "========================================"

    # CRITICAL: Store token BEFORE deferring
    interaction_token = nil
    if event.respond_to?(:token) && event.token.present?
      interaction_token = event.token
    elsif event.respond_to?(:interaction) && event.interaction.respond_to?(:token) && event.interaction.token.present?
      interaction_token = event.interaction.token
    end

    # CRITICAL: Defer response IMMEDIATELY
    begin
      event.defer_update
      @discord_logger.info "Deferred update sent for loot roll"
    rescue => e
      @discord_logger.error "Failed to defer loot roll update: #{e.message}"
      return
    end

    custom_id = event.custom_id
    # Format: loot_roll_{loot_roll_id}_{action}
    # action can be "roll" or "tiebreaker"
    parts = custom_id.split("_")

    unless parts.length >= 4
      @discord_logger.error "Invalid loot_roll format: #{custom_id}"
      send_followup_via_webhook_with_token(interaction_token, "Invalid loot roll format", ephemeral: true)
      return
    end

    loot_roll_id = parts[2].to_i
    action = parts[3] # "roll" or "tiebreaker"

    discord_user_id = event.user.id.to_s
    discord_username = "#{event.user.username}##{event.user.discriminator}"

    # Process in background thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          loot_roll = LootRoll.find_by(id: loot_roll_id)
          unless loot_roll
            send_followup_via_webhook_with_token(interaction_token, "Loot roll not found", ephemeral: true)
            next
          end

          # Get Discord display name from member data
          discord_display_name = nil
          member_roles = []
          begin
            guild_setting = loot_roll.guild.guild_discord_setting
            if guild_setting&.discord_guild_id.present?
              bot_token = guild_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
              service = DiscordService.new(bot_token: bot_token)
              member = service.get_guild_member(guild_setting.discord_guild_id, discord_user_id)
              if member
                discord_display_name = member["nick"] || member["user"]["global_name"] || member["user"]["username"]
                member_roles = member["roles"] || []
              end
            end
          rescue => e
            @discord_logger.warn "Could not fetch Discord member info: #{e.message}"
          end
          discord_display_name ||= discord_username

          case action
          when "roll"
            handle_loot_roll_initial_gateway(loot_roll, discord_user_id, discord_username, discord_display_name, member_roles, interaction_token)
          when "tiebreaker"
            handle_loot_roll_tiebreaker_gateway(loot_roll, discord_user_id, discord_display_name, member_roles, interaction_token)
          else
            send_followup_via_webhook_with_token(interaction_token, "Unknown action", ephemeral: true)
          end
        rescue => e
          @discord_logger.error "Loot roll error: #{e.class.name}: #{e.message}"
          @discord_logger.error e.backtrace.first(10).join("\n")
          send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
        end
      end
    end
  rescue => e
    @discord_logger.error "Loot roll interaction error: #{e.class.name}: #{e.message}"
    @discord_logger.error e.backtrace.first(10).join("\n")
  end

  def handle_alliance_poll_vote_interaction(event)
    interaction_token = nil
    if event.respond_to?(:token) && event.token.present?
      interaction_token = event.token
    elsif event.respond_to?(:interaction) && event.interaction.respond_to?(:token) && event.interaction.token.present?
      interaction_token = event.interaction.token
    end

    begin
      event.defer_update
    rescue => e
      @discord_logger.error "Failed to defer alliance poll vote: #{e.message}"
      return
    end

    custom_id = event.custom_id
    rest = custom_id.delete_prefix("alliance_poll_vote_")
    poll_id_str, choice_str = rest.split("_", 2)
    poll_id = poll_id_str.to_i
    choice_map = { "yes" => 0, "no" => 1, "maybe" => 2 }
    choice = choice_map[choice_str]

    unless choice
      send_followup_via_webhook_with_token(interaction_token, "Invalid vote choice", ephemeral: true)
      return
    end

    discord_user_id = event.user.id.to_s

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          poll = AlliancePoll.find_by(id: poll_id)
          unless poll
            send_followup_via_webhook_with_token(interaction_token, "Poll not found", ephemeral: true)
            next
          end

          unless poll.open?
            send_followup_via_webhook_with_token(interaction_token, "This poll is closed", ephemeral: true)
            next
          end

          user_discord_connection = UserDiscordConnection.find_by(discord_user_id: discord_user_id)
          unless user_discord_connection
            send_followup_via_webhook_with_token(interaction_token, "Please connect your Discord account to GuildSync to vote", ephemeral: true)
            next
          end

          user = user_discord_connection.user
          unless poll.alliance.alliance_members.where(user_id: user.id, status: :active).exists?
            send_followup_via_webhook_with_token(interaction_token, "You must be an alliance member to vote", ephemeral: true)
            next
          end

          vote = poll.alliance_poll_votes.find_or_initialize_by(user: user)
          vote.choice = choice

          if vote.save
            DiscordAlliancePollService.update_all_linked_messages(poll.reload)
            begin
              AlliancePollsChannel.broadcast_vote_update(poll)
            rescue StandardError => cable_err
              @discord_logger.warn "[AlliancePoll] Action Cable broadcast failed: #{cable_err.class}: #{cable_err.message}"
            end
            choice_labels = { 0 => "✅ Yes", 1 => "❌ No", 2 => "🤔 Maybe" }
            send_followup_via_webhook_with_token(interaction_token, "Vote recorded: #{choice_labels[choice]}", ephemeral: true)
          else
            send_followup_via_webhook_with_token(interaction_token, "Failed to save vote: #{vote.errors.full_messages.join(', ')}", ephemeral: true)
          end
        rescue => e
          @discord_logger.error "Alliance poll vote error: #{e.class.name}: #{e.message}"
          send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
        end
      end
    end
  rescue => e
    @discord_logger.error "Alliance poll interaction error: #{e.class.name}: #{e.message}"
  end

  def handle_alliance_loot_roll_interaction(event)
    interaction_token = nil
    if event.respond_to?(:token) && event.token.present?
      interaction_token = event.token
    elsif event.respond_to?(:interaction) && event.interaction.respond_to?(:token) && event.interaction.token.present?
      interaction_token = event.interaction.token
    end

    begin
      event.defer_update
    rescue => e
      @discord_logger.error "Failed to defer alliance loot roll: #{e.message}"
      return
    end

    custom_id = event.custom_id
    rest = custom_id.delete_prefix("alliance_loot_roll_")
    m = rest.match(/\A(\d+)_(.+)\z/)
    unless m
      send_followup_via_webhook_with_token(interaction_token, "Invalid loot roll format", ephemeral: true)
      return
    end

    loot_roll_id = m[1].to_i
    action = m[2]
    unless action == "roll"
      send_followup_via_webhook_with_token(interaction_token, "Unknown action", ephemeral: true)
      return
    end

    discord_user_id = event.user.id.to_s

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          loot_roll = AllianceLootRoll.find_by(id: loot_roll_id)
          unless loot_roll
            send_followup_via_webhook_with_token(interaction_token, "Loot roll not found", ephemeral: true)
            next
          end

          unless loot_roll.currently_open?
            send_followup_via_webhook_with_token(interaction_token, "This loot roll is closed", ephemeral: true)
            next
          end

          user_discord_connection = UserDiscordConnection.find_by(discord_user_id: discord_user_id)
          unless user_discord_connection
            send_followup_via_webhook_with_token(interaction_token, "Please connect your Discord account to GuildSync to roll", ephemeral: true)
            next
          end

          user = user_discord_connection.user
          unless loot_roll.alliance.alliance_members.where(user_id: user.id, status: :active).exists?
            send_followup_via_webhook_with_token(interaction_token, "You must be an alliance member to roll", ephemeral: true)
            next
          end

          if loot_roll.alliance_loot_roll_entries.exists?(user_id: user.id)
            send_followup_via_webhook_with_token(interaction_token, "You have already rolled", ephemeral: true)
            next
          end

          display_name = gateway_interaction_member_display_name(event).presence
          server_id = event.respond_to?(:server) && event.server ? event.server.id.to_s : nil
          if display_name.blank? && server_id.present?
            g = DiscordGuildMemberLabel.guild_from_discord_snowflake(server_id)
            display_name = DiscordGuildMemberLabel.for_user_in_guild(user: user, guild: g, cache: {}) if g
          end
          display_name ||= gateway_discord_user_display_name(event.user)
          display_name = DiscordGuildMemberLabel.fallback_label(user) if display_name.blank?

          entry = loot_roll.alliance_loot_roll_entries.create!(
            user: user,
            display_name: display_name
          )

          DiscordAllianceLootRollService.update_all_linked_messages(loot_roll.reload)
          begin
            AllianceLootRollsChannel.broadcast_update(loot_roll.reload)
          rescue StandardError => e
            @discord_logger.error "Failed to broadcast alliance loot roll update: #{e.message}"
          end
          send_followup_via_webhook_with_token(interaction_token, "🎲 You rolled **#{entry.roll_value}**!", ephemeral: true)
        rescue ActiveRecord::RecordInvalid => e
          send_followup_via_webhook_with_token(interaction_token, e.record.errors.full_messages.first || "Failed to record roll", ephemeral: true)
        rescue => e
          @discord_logger.error "Alliance loot roll error: #{e.class.name}: #{e.message}"
          send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
        end
      end
    end
  rescue => e
    @discord_logger.error "Alliance loot roll interaction error: #{e.class.name}: #{e.message}"
  end

  def handle_loot_roll_initial_gateway(loot_roll, discord_user_id, discord_username, discord_display_name, member_roles, interaction_token)
    # Check if loot roll is still open
    unless loot_roll.currently_open?
      send_followup_via_webhook_with_token(interaction_token, "This loot roll is closed.", ephemeral: true)
      return
    end

    # Check if there's a tie in progress - if so, only tiebreaker button works
    if loot_roll.has_tie?
      send_followup_via_webhook_with_token(interaction_token, "A tie-breaker is in progress. Only tied users can reroll.", ephemeral: true)
      return
    end

    # Check if user has already rolled (and not invalidated)
    existing_entry = loot_roll.loot_roll_entries.find_by(discord_user_id: discord_user_id.to_s, is_reroll: false)
    if existing_entry
      send_followup_via_webhook_with_token(interaction_token, "You have already rolled.", ephemeral: true)
      return
    end

    # Check if user has an allowed role (if roles are configured)
    # Skip role check if:
    # 1. No roles are configured (empty allowed_role_ids)
    # 2. @everyone is selected (guild ID is in allowed_role_ids - Discord doesn't return @everyone in member roles)
    if loot_roll.allowed_role_ids.present? && loot_roll.allowed_role_ids.any?
      allowed_ids = loot_roll.allowed_role_ids.map(&:to_s)
      discord_guild_id = loot_roll.guild.guild_discord_setting&.discord_guild_id.to_s

      # If @everyone (guild ID) is in allowed roles, skip the check - everyone can roll
      unless allowed_ids.include?(discord_guild_id)
        # Check if user has any of the allowed roles
        unless member_roles.any? { |role_id| allowed_ids.include?(role_id.to_s) }
          send_followup_via_webhook_with_token(interaction_token, "You don't have permission to roll. Required roles not found.", ephemeral: true)
          return
        end
      end
    end

    # Generate server-side random roll
    roll_value = rand(loot_roll.min_roll..loot_roll.max_roll)

    # Get user's highest role position
    discord_role_position = get_highest_role_position_for_loot_roll(loot_roll.guild, member_roles)

    # Create entry
    loot_roll.loot_roll_entries.create!(
      discord_user_id: discord_user_id.to_s,
      display_name: discord_display_name || discord_username || "Unknown",
      roll_value: roll_value,
      discord_role_position: discord_role_position
    )

    # Update Discord message
    update_loot_roll_discord_and_broadcast(loot_roll)

    # Send confirmation
    send_followup_via_webhook_with_token(interaction_token, "🎲 You rolled **#{roll_value}**!", ephemeral: true)
    @discord_logger.info "Loot roll entry created - user: #{discord_display_name}, roll: #{roll_value}"
  end

  def handle_loot_roll_tiebreaker_gateway(loot_roll, discord_user_id, discord_display_name, member_roles, interaction_token)
    # Check if there's actually a tie
    unless loot_roll.has_tie?
      send_followup_via_webhook_with_token(interaction_token, "No tie-breaker needed.", ephemeral: true)
      return
    end

    # Check if user is one of the tied users
    tied_user_ids = loot_roll.tied_user_ids
    unless tied_user_ids.include?(discord_user_id.to_s)
      send_followup_via_webhook_with_token(interaction_token, "You are not part of the tie. Only tied users can reroll.", ephemeral: true)
      return
    end

    # Check if user has already rerolled for this tiebreaker round
    user_entry = loot_roll.loot_roll_entries.active.find_by(discord_user_id: discord_user_id.to_s)
    if user_entry&.tiebreaker_round.to_i >= loot_roll.current_tiebreaker_round
      send_followup_via_webhook_with_token(interaction_token, "You have already rerolled for this tie-breaker round. Waiting for other tied users.", ephemeral: true)
      return
    end

    # Generate new roll
    new_roll_value = rand(loot_roll.min_roll..loot_roll.max_roll)

    # Update the user's entry with the new roll and increment tiebreaker round
    user_entry.update!(
      roll_value: new_roll_value,
      tiebreaker_round: loot_roll.current_tiebreaker_round
    )

    # Check if all tied users have rerolled
    loot_roll.check_tiebreaker_complete!

    # Update Discord message
    update_loot_roll_discord_and_broadcast(loot_roll)

    # Send confirmation
    send_followup_via_webhook_with_token(interaction_token, "🎲 Tie-breaker: You rolled **#{new_roll_value}**!", ephemeral: true)
    @discord_logger.info "Loot roll tiebreaker - user: #{discord_display_name}, roll: #{new_roll_value}"
  end

  def update_loot_roll_discord_and_broadcast(loot_roll)
    begin
      DiscordLootRollService.new(loot_roll).update_loot_roll_message
    rescue => e
      @discord_logger.error "Failed to update Discord loot roll message: #{e.message}"
      @discord_logger.error e.backtrace.first(5).join("\n")
    end

    begin
      LootRollsChannel.broadcast_update(loot_roll)
    rescue => e
      @discord_logger.error "Failed to broadcast loot roll update: #{e.message}"
    end
  end

  def get_highest_role_position_for_loot_roll(guild, member_role_ids)
    return 999 if member_role_ids.empty?

    begin
      discord_setting = guild.guild_discord_setting
      return 999 unless discord_setting&.connected?

      bot_token = discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
      response = RestClient.get(
        "https://discord.com/api/v10/guilds/#{discord_setting.discord_guild_id}/roles",
        { "Authorization" => "Bot #{bot_token}" }
      )

      roles = JSON.parse(response.body)
      user_role_positions = roles.select { |r| member_role_ids.include?(r["id"]) }.map { |r| r["position"] }

      user_role_positions.max || 999
    rescue => e
      @discord_logger.error "Failed to fetch role positions: #{e.message}"
      999
    end
  end

  def handle_status_selection(button_event)
    # CRITICAL: Store token BEFORE deferring (token might not be accessible after)
    interaction_token = nil
    if button_event.respond_to?(:token) && button_event.token.present?
      interaction_token = button_event.token
    elsif button_event.respond_to?(:interaction) && button_event.interaction.respond_to?(:token) && button_event.interaction.token.present?
      interaction_token = button_event.interaction.token
    end

    @discord_logger.info "Stored interaction token: #{interaction_token[0..20] if interaction_token}..."

    # CRITICAL: Defer response IMMEDIATELY - must be first thing we do
    # Use defer_update (same as handle_event_signup_via_gateway) then send ephemeral followup
    begin
      button_event.defer_update
      @discord_logger.info "Deferred update sent to Discord"
    rescue => e
      @discord_logger.error "Failed to defer update: #{e.message}"
      @discord_logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      # If defer fails, try to respond directly
      begin
        button_event.respond(content: "Processing...", ephemeral: true)
      rescue => e2
        @discord_logger.error "Failed to send any response: #{e2.message}"
      end
      return
    end

    custom_id = button_event.custom_id
    parts = custom_id.split("_")

    @discord_logger.info "Status selection - custom_id: #{custom_id}, parts: #{parts.inspect}"

    # Format: event_status_{event_id}_{role}_{status}_{user_id}
    # Problem: "on_time" has underscore, so we need to parse intelligently
    if parts.length >= 6
      event_id = parts[2].to_i
      role = parts[3]

      # Valid statuses (removed tentative - only on_time, late, absent)
      valid_statuses = [ "on_time", "late", "absent", "remove" ]

      # Try to find the status - it might be "on_time" (2 parts) or single word
      status = nil
      user_id_start_index = nil

      # Check if parts[4] + parts[5] forms "on_time"
      if parts.length >= 7 && "#{parts[4]}_#{parts[5]}" == "on_time"
        status = "on_time"
        user_id_start_index = 6
      else
        # Single word status
        status = parts[4]
        user_id_start_index = 5
      end

      # Validate status
      unless valid_statuses.include?(status)
        @discord_logger.error "Invalid status: #{status}. Valid: #{valid_statuses.inspect}"
        if interaction_token
          send_followup_via_webhook_with_token(interaction_token, "Invalid status selection", ephemeral: true)
        end
        return
      end

      # Get user_id (everything after status)
      user_id = parts[user_id_start_index..-1].join("_") if user_id_start_index

      # Store user data BEFORE starting thread (button_event might not be thread-safe)
      actual_user_id = button_event.user.id.to_s
      discord_login = gateway_discord_login(button_event.user)
      prefetch_nick = gateway_interaction_member_display_name(button_event)
      prefetch_display_user = gateway_discord_user_display_name(button_event.user)

      # Process in background thread to avoid blocking and handle errors gracefully
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            discord_event = DiscordEvent.find_by(id: event_id)
            unless discord_event
              if interaction_token
                send_followup_via_webhook_with_token(interaction_token, "Event not found", ephemeral: true)
              end
              next
            end

            # Get display name (server nickname) from Discord member
            discord_display_name = nil
            begin
              guild_id = discord_event.guild.discord_id || discord_event.guild.guild_discord_setting&.discord_guild_id
              if guild_id
                bot_token = discord_event.guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
                service = DiscordService.new(bot_token: bot_token)
                member = service.get_guild_member(guild_id, actual_user_id)
                if member
                  discord_display_name = DiscordGuildMemberLabel.from_member_json(member)
                end
              end
            rescue => e
              @discord_logger.warn "Could not fetch Discord member display name: #{e.message}"
            end
            discord_display_name ||= prefetch_nick
            discord_display_name ||= prefetch_display_user
            discord_display_name ||= discord_login

            @discord_logger.info "Parsed - event_id: #{event_id}, role: #{role}, status: #{status}, user_id from button: #{user_id}, actual_user_id: #{actual_user_id}"

            message = nil
            if status == "remove"
              signup = discord_event.discord_event_signups.find_by(
                discord_user_id: actual_user_id
              )
              if signup
                signup.destroy
                message = "✅ Removed from event signup"
                @discord_logger.info "Signup removed"
              else
                message = "Signup not found"
                @discord_logger.warn "Signup not found for removal"
              end
            else
              # Find or initialize signup (one per user per event)
              signup = discord_event.discord_event_signups.find_or_initialize_by(
                discord_user_id: actual_user_id
              )

              # Update role and status
              # Always set role (required by validation) - it comes from the button clicked
              signup.role = role
              signup.status = status
              signup.discord_username = discord_login
              signup.discord_display_name = discord_display_name if signup.respond_to?(:discord_display_name=)
              signup.save!

              status_messages = {
                "on_time" => "✅ On Time",
                "late" => "⏰ Late",
                "absent" => "❌ Absent"
              }
              message = "✅ Updated: **#{role.upcase}** - **#{status_messages[status]}**"
              @discord_logger.info "Signup saved - role: #{role}, status: #{status}"
            end

            # Update embed
            update_discord_message_embed(discord_event)

            # Use followup message since we already deferred the response
            if interaction_token && message
              send_followup_via_webhook_with_token(interaction_token, message, ephemeral: true)
              @discord_logger.info "Followup message sent: #{message[0..50]}..."
            else
              @discord_logger.error "Cannot send followup: interaction_token=#{interaction_token.present?}, message=#{message.present?}"
            end
          rescue => e
            @discord_logger.error "Status selection processing error: #{e.class.name}: #{e.message}"
            @discord_logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
            if interaction_token
              begin
                send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
              rescue => followup_error
                @discord_logger.error "Failed to send error followup: #{followup_error.message}"
              end
            else
              @discord_logger.error "Cannot send error followup: interaction_token is missing"
            end
          end
        end
      end
    else
      @discord_logger.error "Invalid status selection format - parts.length: #{parts.length}, custom_id: #{custom_id}"
      if interaction_token
        send_followup_via_webhook_with_token(interaction_token, "Invalid status selection format", ephemeral: true)
      end
    end
  rescue => e
    @discord_logger.error "Status selection error: #{e.class.name}: #{e.message}"
    @discord_logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
    if interaction_token
      send_followup_via_webhook_with_token(interaction_token, "An error occurred. Please try again.", ephemeral: true)
    end
  end

  def format_usernames_in_columns(usernames, max_per_column = 5)
    return "```None```" if usernames.empty?

    # Split into columns of max_per_column
    columns = usernames.each_slice(max_per_column).to_a

    if columns.length == 1
      # Single column - just list them vertically
      "```#{columns[0].join("\n")}```"
    else
      # Multiple columns - format vertically, one name per line
      # Discord will display inline fields side by side, so we keep it simple
      "```#{usernames.join("\n")}```"
    end
  end

  def update_discord_message_embed(discord_event)
    return unless discord_event.discord_message_id && discord_event.channel_id

    # Validate that IDs are proper Discord snowflakes (numeric strings, 17-19 digits)
    unless discord_event.discord_message_id.match?(/^\d{17,19}$/) && discord_event.channel_id.match?(/^\d{17,19}$/)
      @discord_logger.warn "Skipping message update - invalid Discord snowflake IDs (message_id: #{discord_event.discord_message_id}, channel_id: #{discord_event.channel_id})"
      return
    end

    role_emojis = DiscordEvent::ROLE_EMOJIS
    roles = discord_event.role_categories.presence || DiscordEvent::ROLE_CATEGORIES

    # Format scheduled time for description (on same line)
    scheduled_time_formatted = "<t:#{discord_event.scheduled_at.to_i}:F>"
    description_text = discord_event.description || "Join us for this event!"
    description_with_time = "**⏰ Scheduled:** #{scheduled_time_formatted}\n\n#{description_text}"

    fields = []

    # Count total - on_time + late (NOT absent)
    on_time_count = discord_event.discord_event_signups.where(status: "on_time").count
    late_count = discord_event.discord_event_signups.where(status: "late").count
    total_count = on_time_count + late_count

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
      value: "**#{total_count}**",
      inline: true
    }
    fields += row1_fields

    # Role signups in columns (inline for width)
    # Only show and count on_time users in role sections
    roles.each do |role|
      # Get only on_time signups for this role
      on_time_signups = discord_event.discord_event_signups.where(role: role, status: "on_time").to_a

      # Get display name (preferred) or username (fallback)
      display_name_method = ->(signup) {
        signup.respond_to?(:discord_display_name) && signup.discord_display_name.present? ?
          signup.discord_display_name : signup.discord_username
      }

      # Format display names in columns (up to 5 per column)
      if on_time_signups.any?
        display_names = on_time_signups.map(&display_name_method)
        value = format_usernames_in_columns(display_names)
      else
        value = "```None```"
      end

      # Count only on_time signups
      fields << {
        name: "**#{role_emojis[role]} #{role.upcase} (#{on_time_signups.count})**",
        value: value,
        inline: true
      }
    end

    # Collect late and absent signups for bottom section (for leader visibility)
    all_late = discord_event.discord_event_signups.where(status: "late").map { |s|
      s.respond_to?(:discord_display_name) && s.discord_display_name.present? ? s.discord_display_name : s.discord_username
    }
    all_absent = discord_event.discord_event_signups.where(status: "absent").map { |s|
      s.respond_to?(:discord_display_name) && s.discord_display_name.present? ? s.discord_display_name : s.discord_username
    }

    # Status sections at bottom (always show, like before)
    fields << {
      name: "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
      value: "**STATUS**",
      inline: false
    }
    fields << {
      name: "**⏰ Late**",
      value: all_late.any? ? format_usernames_in_columns(all_late) : "**None**",
      inline: true
    }
    fields << {
      name: "**❌ Absent**",
      value: all_absent.any? ? format_usernames_in_columns(all_absent) : "**None**",
      inline: true
    }

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

    role_rows = roles.each_slice(5).map do |batch|
      {
        type: 1,
        components: batch.map do |role|
          {
            type: 2,
            style: 1,
            label: "#{role_emojis[role]} #{role.upcase}",
            custom_id: "event_signup_#{discord_event.id}_#{role}"
          }
        end
      }
    end

    bot_token = discord_event.guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
    service = DiscordService.new(bot_token: bot_token)
    service.update_message(
      discord_event.channel_id,
      discord_event.discord_message_id,
      "**🎯 Event Signups** - Click buttons below to sign up:",
      embed: embed,
      components: role_rows
    )
  rescue => e
    # Don't log expected errors as errors - they're handled gracefully
    if e.is_a?(RestClient::ExceptionWithResponse)
      case e.response&.code
      when 429
        @discord_logger.warn "Rate limited while updating Discord message - will retry on next update"
      when 404
        @discord_logger.warn "Message/channel not found (404) - may have been deleted or IDs invalid"
      else
        @discord_logger.error "Failed to update Discord message: #{e.response&.code} - #{e.message}"
        @discord_logger.error e.backtrace.first(5).join("\n")
      end
    else
      @discord_logger.error "Failed to update Discord message: #{e.message}"
      @discord_logger.error e.backtrace.first(5).join("\n")
    end
  end

  # discordrb user: prefer Discord display name (global_name / server nick) over login username.
  def gateway_discord_user_display_name(user)
    return "Unknown" unless user
    if user.respond_to?(:global_name) && user.global_name.present?
      user.global_name
    elsif user.respond_to?(:nick) && user.nick.present?
      user.nick
    else
      user.username.to_s
    end
  end

  def gateway_discord_login(dr_user)
    return "unknown" unless dr_user
    u = dr_user.username.to_s
    d = dr_user.respond_to?(:discriminator) ? dr_user.discriminator.to_s : ""
    (d.present? && d != "0") ? "#{u}##{d}" : u
  end

  # Server nickname from gateway member when discordrb exposes it.
  def gateway_interaction_member_display_name(button_event)
    m = button_event.respond_to?(:member) ? button_event.member : nil
    return nil unless m
    if m.respond_to?(:nick) && m.nick.to_s.present?
      return m.nick.to_s
    end
    if m.respond_to?(:display_name) && m.display_name.present?
      return m.display_name.to_s
    end
    nil
  end

  # ──────────────────────────────────────────────────────────────────────────
  # React roles gateway handler
  # ──────────────────────────────────────────────────────────────────────────

  def handle_react_role_event(event, action)
    # Use gateway payload ID directly; event.message can be nil if message lookup fails.
    message_id = event.message_id.to_s
    server_id  = event.server&.id&.to_s

    # Locate the guild by matching the react_roles message_id
    react_role = ReactRole.includes(:guild).find_by(message_id: message_id)
    return unless react_role

    guild = react_role.guild
    return unless guild

    # Safety check: ensure this event originates from the correct Discord server.
    # Use the same guild-id resolution fallback used elsewhere in Discord features.
    resolved_guild_id = guild.discord_id.presence || guild.guild_discord_setting&.discord_guild_id
    return if server_id.present? && resolved_guild_id.present? && resolved_guild_id.to_s != server_id

    user_id   = event.user.id.to_s
    emoji     = event.emoji
    emoji_name = emoji.name
    emoji_id   = emoji.id&.to_s

    service = DiscordReactRolesService.new(guild)

    if action == :add
      service.handle_reaction_add(user_id, message_id, emoji_name, emoji_id)
    else
      service.handle_reaction_remove(user_id, message_id, emoji_name, emoji_id)
    end
  rescue => e
    @discord_logger.error "[ReactRoles] handle_react_role_event error (#{action}): #{e.class}: #{e.message}"
    @discord_logger.error e.backtrace.first(5).join("\n")
  end
end
