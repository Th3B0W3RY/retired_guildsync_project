# Load rbnacl for Ed25519 signature verification
begin
  require "rbnacl"
rescue LoadError
  # Will be handled in verify_discord_signature!
end

class DiscordController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  before_action :verify_discord_signature!

  # Discord sends PING, MESSAGE_COMPONENT, APPLICATION_COMMAND, etc.
  def interactions
    # Parse JSON body first
    @interaction = JSON.parse(request.raw_post)
    
    case @interaction["type"]
    when 1
      render json: { type: 1 }, status: :ok
      return

    when 2
      handle_application_command
      return

    when 3
      handle_component_interaction
      return

    when 5
      handle_modal_submit
      return

    else
      render json: { type: 4, data: { content: "Unhandled interaction type", flags: 64 } }, status: :ok
      return
    end
  end

  private

  # --- SECURE SIGNATURE CHECK ---
  def verify_discord_signature!
    timestamp = request.headers["X-Signature-Timestamp"]
    signature = request.headers["X-Signature-Ed25519"]
    body = request.raw_post

    return head :unauthorized unless timestamp && signature

    public_key = ENV["DISCORD_PUBLIC_KEY"]
    
    # Allow in development if key not set
    if !public_key && (Rails.env.development? || Rails.env.test?)
      Rails.logger.warn "DISCORD_PUBLIC_KEY not set - allowing in development/test"
      return true
    end
    
    return head :unauthorized unless public_key

    # Allow test signatures in development
    if (Rails.env.development? || Rails.env.test?) && signature == "0" * 128
      Rails.logger.warn "Test signature detected - allowing in development/test"
      return true
    end

    # Use rbnacl for signature verification (more reliable than ed25519 gem)
    unless defined?(RbNaCl)
      Rails.logger.error "rbnacl gem not available"
      return head :unauthorized
    end

    begin
      message = "#{timestamp}#{body}"
      signature_bytes = [signature].pack("H*")
      public_key_bytes = [public_key].pack("H*")
      
      verify_key = RbNaCl::VerifyKey.new(public_key_bytes)
      verify_key.verify(signature_bytes, message)
    rescue RbNaCl::BadSignatureError
      Rails.logger.error "Discord signature verification FAILED"
      head :unauthorized
    rescue => e
      Rails.logger.error "Signature verification error: #{e.message}"
      head :unauthorized
    end
  end

  # --- HANDLE SLASH COMMANDS (type: 2) ---
  def handle_application_command
    command_name = @interaction.dig("data", "name")

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
      "help"        => DiscordHelpCommandService
    }

    service = service_map[command_name]
    if service
      result = service.handle(@interaction)
      render json: result, status: :ok, content_type: "application/json"
    elsif command_name == "signup"
      handle_signup_command
    elsif command_name == "gear"
      handle_gear_command
    else
      render json: {
        type: 4,
        data: { content: I18n.t("discord.commands.errors.not_implemented"), flags: 64 }
      }, status: :ok
    end
  rescue => e
    Rails.logger.error "[DiscordController] Application command error: #{e.class}: #{e.message}"
    render json: {
      type: 4,
      data: { content: "An error occurred processing your command. Please try again.", flags: 64 }
    }, status: :ok
  end

  def handle_signup_command
    member = @interaction["member"]
    data = @interaction["data"]
    options = data["options"] || []
    role_option = options.find { |opt| opt["name"] == "role" }

    unless role_option
      return render json: {
        type: 4,
        data: { content: "Usage: /signup role:<dps|tank|healer|ranged> [event:<event_id>]", flags: 64 }
      }, status: :ok
    end

    role = role_option["value"]
    event_option = options.find { |opt| opt["name"] == "event" }

    if event_option
      event_id = event_option["value"].to_i
    else
      message_id = @interaction.dig("message", "id")
      discord_event = DiscordEvent.find_by(discord_message_id: message_id) if message_id
      event_id = discord_event&.id
    end

    unless event_id
      return render json: {
        type: 4,
        data: { content: "Event not found. Please specify event ID or use this command in reply to an event message.", flags: 64 }
      }, status: :ok
    end

    interaction_token = @interaction["token"]
    discord_user_id = member["user"]["id"]
    discord_username = member["user"]["username"]
    discord_username += "##{member['user']['discriminator']}" if member["user"]["discriminator"].present?

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          de = DiscordEvent.find_by(id: event_id)
          unless de
            send_followup(interaction_token, "Event not found")
            next
          end
          show_attendance_selection(interaction_token, de, role, discord_user_id)
        rescue => e
          Rails.logger.error "Signup command error: #{e.message}"
          send_followup(interaction_token, "An error occurred. Please try again.")
        end
      end
    end

    render json: { type: 5 }, status: :ok, content_type: "application/json"
  end

  def handle_gear_command
    data = @interaction["data"]
    options = data["options"] || []
    subcommand = options.find { |opt| opt["type"] == 1 }
    subcommand_name = subcommand&.dig("name")&.to_sym || :upload

    if subcommand_name == :upload
      interaction_token = @interaction["token"]
      render json: { type: 5 }, status: :ok, content_type: "application/json"
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            result = DiscordGearService.handle_upload_command(@interaction)
            if result&.dig(:data, :content)
              send_followup(interaction_token, result[:data][:content], ephemeral: result[:data][:flags] == 64)
            else
              send_followup(interaction_token, "An error occurred processing your upload.", ephemeral: true)
            end
          rescue => e
            Rails.logger.error "Gear upload error: #{e.message}"
            send_followup(interaction_token, "An error occurred processing your upload.", ephemeral: true)
          end
        end
      end
      return
    end

    result = case subcommand_name
             when :my              then DiscordGearService.handle_my_command(@interaction)
             when :request         then DiscordGearService.handle_request_command(@interaction)
             when :request_missing then DiscordGearService.handle_request_missing_command(@interaction)
             else { type: 4, data: { content: "Unknown gear subcommand", flags: 64 } }
             end

    render json: (result || { type: 4, data: { content: "An error occurred.", flags: 64 } }), status: :ok, content_type: "application/json"
  rescue => e
    Rails.logger.error "Gear command error: #{e.message}"
    render json: { type: 4, data: { content: "An error occurred.", flags: 64 } }, status: :ok
  end

  def handle_modal_submit
    render json: { type: 4, data: { content: "Unknown modal", flags: 64 } }, status: :ok
  end

  def send_followup(token, content, ephemeral: true)
    return unless token.present?
    app_id = ENV["DISCORD_CLIENT_ID"]
    bot_token = ENV["DISCORD_BOT_TOKEN"]
    payload = { content: content }
    payload[:flags] = 64 if ephemeral
    RestClient.post(
      "https://discord.com/api/v10/webhooks/#{app_id}/#{token}",
      payload.to_json,
      { "Authorization" => "Bot #{bot_token}", "Content-Type" => "application/json" }
    )
  rescue => e
    Rails.logger.error "Follow-up failed: #{e.message}"
  end

  def show_attendance_selection(token, discord_event, role, user_id)
    components = [{
      type: 1,
      components: [
        { type: 2, style: 1, label: "On Time",  custom_id: "event_status_#{discord_event.id}_#{role}_on_time_#{user_id}" },
        { type: 2, style: 2, label: "Late",     custom_id: "event_status_#{discord_event.id}_#{role}_late_#{user_id}" },
        { type: 2, style: 4, label: "Absent",   custom_id: "event_status_#{discord_event.id}_#{role}_absent_#{user_id}" },
        { type: 2, style: 4, label: "Remove",   custom_id: "event_status_#{discord_event.id}_#{role}_remove_#{user_id}" }
      ]
    }]
    send_followup(token, "You selected **#{role.upcase}**. Choose your attendance status:")
    app_id = ENV["DISCORD_CLIENT_ID"]
    bot_token = ENV["DISCORD_BOT_TOKEN"]
    RestClient.post(
      "https://discord.com/api/v10/webhooks/#{app_id}/#{token}",
      { content: "Choose attendance:", components: components, flags: 64 }.to_json,
      { "Authorization" => "Bot #{bot_token}", "Content-Type" => "application/json" }
    )
  rescue => e
    Rails.logger.error "Attendance selection error: #{e.message}"
  end

  # --- HANDLE BUTTONS (type: 3) ---
  def handle_component_interaction
    custom_id = @interaction.dig("data", "custom_id")
    interaction_token = @interaction["token"]
    application_id = @interaction["application_id"] || ENV["DISCORD_CLIENT_ID"]

    # ALWAYS ACK IMMEDIATELY (Fixes "Interaction Failed")
    # Type 5 = DEFERRED_UPDATE (for button interactions that update messages)
    render json: { type: 5 }, status: :ok

    # Process logic asynchronously
    # Use perform_now in development to catch errors immediately, perform_later in production
    if Rails.env.development?
      begin
        DiscordInteractionJob.perform_now(custom_id, interaction_token, application_id, @interaction)
      rescue => e
        Rails.logger.error "Discord interaction job failed: #{e.class.name}: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        # Send error followup
        DiscordApi.send_followup(application_id, interaction_token, "An error occurred processing your interaction.", flags: 64)
      end
    else
      DiscordInteractionJob.perform_later(custom_id, interaction_token, application_id, @interaction)
    end
  end
end
