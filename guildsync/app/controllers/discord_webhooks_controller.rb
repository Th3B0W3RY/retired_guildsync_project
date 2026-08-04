# Load rbnacl for Ed25519 signature verification
begin
  require "rbnacl"
rescue LoadError
  # Will be handled in verify_discord_signature
end

class DiscordWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # Use Discord logger for all Discord-related logging
  def discord_logger
    @discord_logger ||= defined?(DiscordLogger) ? DiscordLogger : Rails.logger
  end

  # Discord webhook endpoint for bot interactions (button clicks, etc.)
  def interactions
    # Use raw_post to avoid Rack IO buffering issues
    # request.body.read + rewind causes delays that break Discord's 3-second timeout
    signature = request.headers["X-Signature-Ed25519"]
    timestamp = request.headers["X-Signature-Timestamp"]
    body = request.raw_post

    # SECURITY: Verify Discord signature BEFORE parsing or responding to any request
    # This includes PING requests - Discord signs all requests including PINGs
    unless verify_discord_signature(signature, timestamp, body)
      discord_logger.error "Discord signature verification FAILED"
      # Discord requires HTTP 200 for all interaction responses
      return render json: { type: 4, data: { content: I18n.t("discord.webhooks.invalid_signature"), flags: 64 } }, status: 200
    end

    begin
      interaction = JSON.parse(body)

      # For PING (type 1), respond IMMEDIATELY - no logging, no delays
      if interaction["type"] == 1
        render json: { type: 1 }, status: 200, content_type: "application/json"
        return
      end

      # For all other interactions, respond immediately with deferred response
      # Then log and process in background
      case interaction["type"]
      when 2 # APPLICATION_COMMAND
        handle_application_command(interaction)
      when 3 # MESSAGE_COMPONENT (button clicks)
        handle_message_component(interaction)
      when 5 # MODAL_SUBMIT
        handle_modal_submit(interaction)
      else
        render json: { type: 4, data: { content: I18n.t("discord.webhooks.unknown_interaction_type"), flags: 64 } }, status: 200
      end
    rescue JSON::ParserError => e
      discord_logger.error "JSON parse error: #{e.message}"
      render json: { type: 4, data: { content: I18n.t("discord.webhooks.invalid_request_format"), flags: 64 } }, status: 200
    rescue => e
      discord_logger.error "Discord webhook error: #{e.class.name}: #{e.message}"
      # Always return a valid Discord interaction response, even on error
      render json: {
        type: 4,
        data: {
          content: I18n.t("discord.webhooks.request_processing_error"),
          flags: 64
        }
      }, status: 200
    end
  end

  private

  def verify_discord_signature(signature, timestamp, body)
    return false unless signature && timestamp

    public_key = ENV["DISCORD_PUBLIC_KEY"]
    unless public_key
      discord_logger.warn "DISCORD_PUBLIC_KEY not set - skipping signature verification in development"
      # In development, allow if key not set (for testing)
      return Rails.env.development? || Rails.env.test?
    end

    # In development/test, if signature is all zeros (fake test signature), allow it
    if (Rails.env.development? || Rails.env.test?) && signature == "0" * 128
      discord_logger.warn "Test signature detected (all zeros) - allowing in development/test"
      return true
    end

    unless defined?(RbNaCl)
      discord_logger.error "rbnacl gem not available - run: bundle install"
      return false
    end

    begin
      # Discord uses Ed25519 signatures
      # Format: signature is hex-encoded, public_key is hex-encoded
      # Message to verify: timestamp + body (as raw bytes)
      message = "#{timestamp}#{body}"

      # Convert hex strings to binary
      signature_bytes = [ signature ].pack("H*")
      public_key_bytes = [ public_key ].pack("H*")

      # Verify using rbnacl Ed25519
      verify_key = RbNaCl::VerifyKey.new(public_key_bytes)
      verify_key.verify(signature_bytes, message)

      discord_logger.info "Discord signature verification PASSED (Ed25519)"
      true
    rescue RbNaCl::BadSignatureError => e
      discord_logger.error "Discord signature verification FAILED (bad signature)"
      # Discord requires valid signatures - don't allow invalid ones even in dev
      false
    rescue => e
      discord_logger.error "Signature verification error: #{e.class.name}: #{e.message}"
      discord_logger.error e.backtrace.first(3).join("\n")
      false
    end
  end

  def handle_message_component(interaction)
    # CRITICAL: Send response IMMEDIATELY - no logging, no delays before response
    data = interaction["data"]
    custom_id = data&.dig("custom_id")
    member = interaction["member"] || interaction["user"]

    unless custom_id
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.missing_custom_id"), flags: 64 }
      }, status: 200
    end

    unless member
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.missing_user"), flags: 64 }
      }, status: 200
    end

    # Handle event signup buttons - send deferred response immediately
    if custom_id.start_with?("event_signup_")
      parts = custom_id.split("_")
      if parts.length >= 4
        event_id = parts[2].to_i
        role = parts[3]
        handle_discord_event_signup(interaction, event_id, role, member)
        nil # handle_discord_event_signup already renders response
      else
        render json: {
          type: 4,
          data: { content: I18n.t("discord.webhooks.invalid_event_signup_format"), flags: 64 }
        }, status: 200
      end
    elsif custom_id.start_with?("alliance_event_signup_")
      parts = custom_id.split("_")
      if parts.length >= 5
        alliance_event_id = parts[3].to_i
        role = parts[4]
        handle_alliance_event_signup(interaction, alliance_event_id, role, member)
      else
        render json: {
          type: 4,
          data: { content: I18n.t("discord.webhooks.invalid_alliance_signup_format"), flags: 64 }
        }, status: 200
      end
    elsif custom_id.start_with?("alliance_event_status_")
      parts = custom_id.split("_")
      if parts.length >= 7
        alliance_event_id = parts[3].to_i
        role = parts[4]
        status = parts[5..-2].join("_")
        user_id = parts[-1]
        handle_alliance_event_status_update(interaction, alliance_event_id, role, status, user_id, member)
      else
        render json: {
          type: 4,
          data: { content: I18n.t("discord.webhooks.invalid_alliance_status_format"), flags: 64 }
        }, status: 200
      end
    elsif custom_id.start_with?("event_status_")
      parts = custom_id.split("_")
      if parts.length >= 6
        event_id = parts[2].to_i
        role = parts[3]
        # Status may contain underscores (e.g. "on_time"), so join all
        # middle parts except the final one, which is the user_id.
        status = parts[4..-2].join("_")
        user_id = parts[-1]
        handle_status_update(interaction, event_id, role, status, user_id, member)
        nil # handle_status_update already renders response
      else
        render json: {
          type: 4,
          data: { content: I18n.t("discord.webhooks.invalid_status_update_format"), flags: 64 }
        }, status: 200
      end
    elsif custom_id.start_with?("event_details_")
      event_id = custom_id.split("_").last.to_i
      handle_event_details(interaction, event_id)
      nil # handle_event_details already renders response
    elsif custom_id.start_with?("poll_vote_") || custom_id.start_with?("loot_roll_") ||
          custom_id.start_with?("alliance_poll_vote_") || custom_id.start_with?("alliance_loot_roll_")
      handle_async_component_interaction(interaction, custom_id)
      nil # method renders response
    else
      render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.unknown_interaction_type"), flags: 64 }
      }, status: 200
    end
  rescue => e
    # Log errors in background to avoid delays
    run_async_with_db_connection do
      discord_logger.error "Error in handle_message_component: #{e.class.name}: #{e.message}"
      discord_logger.error e.backtrace.first(10).join("\n") if Rails.env.development?
    end
    # Always return a valid response, even on error
    render json: {
      type: 4,
      data: {
        content: I18n.t("discord.webhooks.request_processing_error"),
        flags: 64
      }
    }, status: 200
  end

  def handle_discord_event_signup(interaction, event_id, role, member)
    # CRITICAL: Send deferred response IMMEDIATELY - no logging before this
    # Discord requires response within 3 seconds - any delay = "Interaction failed"

    # Store variables for background processing BEFORE sending response
    interaction_token = interaction["token"]
    event_id_value = event_id
    role_value = role
    discord_user_id_value = member["user"]["id"]
    discord_display_name_value = discord_member_display_name(member)

    # Start background processing thread FIRST (runs in background)
    # Response is sent AFTER thread starts to ensure immediate acknowledgment
    run_async_with_db_connection do
      begin
        # All logging happens in the background thread to avoid delays
        discord_logger.info "handle_discord_event_signup: event_id=#{event_id_value}, role=#{role_value}"
        discord_logger.info "Processing signup for user: #{discord_display_name_value} (#{discord_user_id_value})"

        discord_event = DiscordEvent.find_by(id: event_id_value)
        unless discord_event
          discord_logger.error "DiscordEvent not found for id=#{event_id_value}"
          send_followup_message(interaction_token, I18n.t("discord.webhooks.event_not_found"))
          next
        end

        unless DiscordEvent::ROLE_CATEGORIES.include?(role_value)
          discord_logger.error "Invalid role: #{role_value}"
          send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.invalid_role"))
          next
        end

        unless can_rsvp_guild_event?(discord_event, discord_user_id_value)
          send_followup_message(interaction_token, account_or_membership_required_message)
          next
        end

        # ALWAYS show attendance selection, even if user already has a signup
        # DO NOT save yet - we'll save when attendance is chosen
        # This allows users to change their role and attendance status anytime
        show_attendance_selection(interaction_token, discord_event, role_value, discord_user_id_value)
      rescue ActiveRecord::RecordInvalid => e
        discord_logger.error "Record validation error: #{e.message}"
        discord_logger.error e.record.errors.full_messages.inspect
        send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.followup_error", message: e.message))
      rescue => e
        discord_logger.error "Discord event signup error: #{e.class.name}: #{e.message}"
        discord_logger.error e.backtrace.first(5).join("\n") if Rails.env.development?
        send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.try_again_short"))
      end
    end

    # CRITICAL: Send deferred response IMMEDIATELY - must be sent within 3 seconds
    # Type 5 = DEFERRED_UPDATE_MESSAGE - tells Discord we'll update the message later
    # This MUST be sent before any database operations or logging
    render json: { type: 5 }, status: 200, content_type: "application/json"
    nil # Explicit return to ensure no further code executes
  end

  def handle_alliance_event_signup(interaction, alliance_event_id, role, member)
    interaction_token = interaction["token"]
    discord_user_id = member.dig("user", "id") || member["id"]
    return render json: { type: 5 }, status: 200, content_type: "application/json" if interaction_token.blank?

    run_async_with_db_connection do
      begin
        event = AllianceEvent.find_by(id: alliance_event_id)
        if event.blank? || !event.role_categories_for_discord.include?(role)
          send_followup_message(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.event_not_found"))
          next
        end

        unless can_rsvp_alliance_event?(event, discord_user_id)
          send_followup_message(interaction_token, account_or_membership_required_message)
          next
        end

        components = AllianceDiscordBroadcastService.attendance_buttons_for(event.id, role, discord_user_id.to_s)
        send_followup_message(
          interaction_token,
          I18n.t("discord.webhooks.alliance_rsvp.attendance_prompt", role: role.upcase),
          components: components
        )
      rescue => e
        discord_logger.error "Alliance signup interaction error: #{e.class.name}: #{e.message}"
        send_followup_message(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.unexpected"))
      end
    end

    render json: { type: 5 }, status: 200, content_type: "application/json"
  end

  def handle_alliance_event_status_update(interaction, alliance_event_id, role, status, user_id, member)
    interaction_token = interaction["token"]
    discord_user_id = member.dig("user", "id") || member["id"]
    discord_display_name = discord_member_display_name(member)
    discord_login = DiscordGuildMemberLabel.username_with_optional_discriminator(member["user"] || {}) ||
                      discord_user_id.to_s

    run_async_with_db_connection do
      begin
        if discord_user_id.to_s != user_id.to_s
          send_followup_message(interaction_token, I18n.t("discord.webhooks.alliance_rsvp.wrong_account_button"))
          next
        end

        result = AllianceDiscordBroadcastService.apply_status_selection(
          event_id: alliance_event_id,
          role: role,
          status: status,
          discord_user_id: discord_user_id.to_s,
          discord_username: discord_login,
          discord_display_name: discord_display_name
        )

        if result[:ok]
          send_followup_message(
            interaction_token,
            I18n.t(
              "discord.webhooks.alliance_rsvp.status_updated",
              role: role.upcase,
              status: discord_rsvp_status_label(status)
            )
          )
        else
          error_message = case result[:error]
          when :link_required
            I18n.t("alliances.events.discord_rsvp.errors.link_required")
          when :event_not_found
            I18n.t("alliances.events.discord_rsvp.errors.event_not_found")
          when :invalid_status
            I18n.t("alliances.events.discord_rsvp.errors.invalid_status")
          when :not_alliance_member
            I18n.t("alliances.events.discord_rsvp.errors.not_alliance_member")
          when :account_or_membership_required
            account_or_membership_required_message
          when :save_failed
            I18n.t("alliances.events.discord_rsvp.errors.save_failed", error: result[:message])
          else
            I18n.t("alliances.events.discord_rsvp.errors.unexpected")
          end
          send_followup_message(interaction_token, error_message)
        end
      rescue => e
        discord_logger.error "Alliance status interaction error: #{e.class.name}: #{e.message}"
        send_followup_message(interaction_token, I18n.t("alliances.events.discord_rsvp.errors.unexpected"))
      end
    end

    render json: { type: 5 }, status: 200, content_type: "application/json"
  end

  def send_followup_message(interaction_token, content, components: nil, ephemeral: true)
    return unless interaction_token.present?

    begin
      bot_token = ENV["DISCORD_BOT_TOKEN"]
      application_id = ENV["DISCORD_CLIENT_ID"]

      payload = { content: content }
      payload[:flags] = 64 if ephemeral # flags: 64 = EPHEMERAL (private to user)
      payload[:components] = components if components.present?

      RestClient.post(
        "https://discord.com/api/v10/webhooks/#{application_id}/#{interaction_token}",
        payload.to_json,
        {
          "Authorization" => "Bot #{bot_token}",
          "Content-Type" => "application/json"
        }
      )
    rescue Exception => e
      discord_logger.error "Failed to send follow-up message: #{e.message}"
    end
  end

  def show_attendance_selection(interaction_token, discord_event, role, user_id)
    # Create attendance status selection buttons
    components = [ {
      type: 1,
      components: [
        {
          type: 2,
          style: 1, # Primary (blue)
          label: I18n.t("discord.webhooks.rsvp.button_on_time"),
          custom_id: "event_status_#{discord_event.id}_#{role}_on_time_#{user_id}"
        },
        {
          type: 2,
          style: 2, # Secondary (gray)
          label: I18n.t("discord.webhooks.rsvp.button_late"),
          custom_id: "event_status_#{discord_event.id}_#{role}_late_#{user_id}"
        },
        {
          type: 2,
          style: 4, # Danger (red)
          label: I18n.t("discord.webhooks.rsvp.button_absent"),
          custom_id: "event_status_#{discord_event.id}_#{role}_absent_#{user_id}"
        },
        {
          type: 2,
          style: 4, # Danger (red)
          label: I18n.t("discord.webhooks.rsvp.button_remove"),
          custom_id: "event_status_#{discord_event.id}_#{role}_remove_#{user_id}"
        }
      ]
    } ]

    send_followup_message(
      interaction_token,
      I18n.t("discord.webhooks.rsvp.attendance_prompt", role: role.upcase),
      components: components
    )
  end

  def update_event_message_embed(discord_event)
    return unless discord_event.discord_message_id && discord_event.channel_id

    # Validate that IDs are proper Discord snowflakes (numeric strings, 17-19 digits)
    unless discord_event.discord_message_id.match?(/^\d{17,19}$/) && discord_event.channel_id.match?(/^\d{17,19}$/)
      discord_logger.warn "Skipping message update - invalid Discord snowflake IDs (message_id: #{discord_event.discord_message_id}, channel_id: #{discord_event.channel_id})"
      return
    end

    signups_by_role = discord_event.signups_by_role
    role_emojis = DiscordEvent::ROLE_EMOJIS
    roles = discord_event.role_categories.presence || DiscordEvent::ROLE_CATEGORIES

    fields = []

    # Count total - on_time + late (NOT absent)
    on_time_count = discord_event.discord_event_signups.where(status: "on_time").count
    late_count = discord_event.discord_event_signups.where(status: "late").count
    total_count = on_time_count + late_count

    # Row 1: Squad Leader, Location, Event Type, Total (all inline)
    row1_fields = []
    if discord_event.respond_to?(:squad_leader) && discord_event.squad_leader.present?
      row1_fields << {
        name: I18n.t("discord.webhooks.event_embed.squad_leader"),
        value: "**#{discord_event.squad_leader}**",
        inline: true
      }
    end
    if discord_event.respond_to?(:location) && discord_event.location.present?
      row1_fields << {
        name: I18n.t("discord.webhooks.event_embed.location"),
        value: "**#{discord_event.location}**",
        inline: true
      }
    end
    type_label = if discord_event.event_type.present?
      discord_event.event_type.humanize
    else
      I18n.t("discord.webhooks.event_embed.general_type")
    end
    row1_fields << {
      name: I18n.t("discord.webhooks.event_embed.event_type"),
      value: "**#{type_label}**",
      inline: true
    }
    row1_fields << {
      name: I18n.t("discord.webhooks.event_embed.total"),
      value: "**#{total_count}**",
      inline: true
    }
    fields += row1_fields

    # Get display name (preferred) or username (fallback)
    display_name_method = ->(signup) {
      signup.respond_to?(:discord_display_name) && signup.discord_display_name.present? ?
        signup.discord_display_name : signup.discord_username
    }

    # Role signups in columns (inline for width)
    # Only show and count on_time users in role sections
    roles.each do |role|
      # Get only on_time signups for this role
      on_time_signups = discord_event.discord_event_signups.where(role: role, status: "on_time").to_a

      # Format display names in columns (up to 5 per column)
      if on_time_signups.any?
        display_names = on_time_signups.map(&display_name_method)
        value = format_usernames_in_columns(display_names)
      else
        value = I18n.t("discord.webhooks.event_embed.none_markdown")
      end

      # Count only on_time signups
      fields << {
        name: "**#{role_emojis[role]} #{role.upcase} (#{on_time_signups.count})**",
        value: value,
        inline: true
      }
    end

    # Collect late and absent signups for bottom section (for leader visibility)
    all_late = discord_event.discord_event_signups.where(status: "late").map(&display_name_method)
    all_absent = discord_event.discord_event_signups.where(status: "absent").map(&display_name_method)

    # Status sections at bottom (always show, like before)
    fields << {
      name: I18n.t("discord.webhooks.event_embed.status_separator"),
      value: I18n.t("discord.webhooks.event_embed.status_heading"),
      inline: false
    }
    none_display = I18n.t("discord.webhooks.event_embed.none_display")
    fields << {
      name: I18n.t("discord.webhooks.event_embed.late"),
      value: all_late.any? ? format_usernames_in_columns(all_late) : none_display,
      inline: true
    }
    fields << {
      name: I18n.t("discord.webhooks.event_embed.absent"),
      value: all_absent.any? ? format_usernames_in_columns(all_absent) : none_display,
      inline: true
    }

    # Format scheduled time for description (on same line)
    scheduled_time_formatted = "<t:#{discord_event.scheduled_at.to_i}:F>"
    description_text = discord_event.description.presence ||
      I18n.t("discord.webhooks.event_embed.default_description")
    scheduled_line = I18n.t("discord.webhooks.event_embed.scheduled_label", timestamp: scheduled_time_formatted)
    description_with_time = "#{scheduled_line}\n\n#{description_text}"

    embed = {
      title: I18n.t("discord.webhooks.event_embed.title", title: discord_event.title),
      description: description_with_time,
      color: 0x5865F2,
      fields: fields,
      timestamp: discord_event.scheduled_at.iso8601,
      footer: {
        text: I18n.t("discord.webhooks.event_embed.footer")
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

    all_components = role_rows

    # Use guild-specific bot token if available, otherwise fall back to environment variable
    bot_token = discord_event.guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
    service = DiscordService.new(bot_token: bot_token)
    service.update_message(
      discord_event.channel_id,
      discord_event.discord_message_id,
      I18n.t("discord.webhooks.event_embed.signup_prompt"),
      embed: embed,
      components: all_components
    )
  rescue => e
    # Don't log expected errors as errors - they're handled gracefully
    if e.is_a?(RestClient::ExceptionWithResponse)
      case e.response.code
      when 429
        discord_logger.warn "Rate limited while updating event message - will retry on next update"
      when 404
        discord_logger.warn "Message/channel not found (404) - may have been deleted or IDs invalid"
      else
        discord_logger.error "Failed to update event message: #{e.response.code} - #{e.message}"
      end
    else
      discord_logger.error "Failed to update event message: #{e.message}"
    end
  end

  def format_usernames_in_columns(usernames, max_per_column = 5)
    return I18n.t("discord.webhooks.event_embed.none_markdown") if usernames.empty?

    # Split into columns of max_per_column
    columns = usernames.each_slice(max_per_column).to_a

    if columns.length == 1
      # Single column - just list them vertically
      "```#{columns[0].join("\n")}```"
    else
      # Multiple columns - format as multiple code blocks side by side
      # Discord inline fields will display them side by side
      columns.map { |col| "```#{col.join("\n")}```" }.join(" ")
    end
  end

  # NOTE: This method uses the legacy Event model, not DiscordEvent
  # If migrating to DiscordEvent, update this method to use DiscordEvent.find_by(id: event_id)
  # and adjust the response format to match DiscordEvent's structure
  def handle_event_details(interaction, event_id)
    event = Event.find_by(id: event_id)

    unless event
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.event_not_found"), flags: 64 }
      }, status: 200
    end

    participants_count = event.participants.count + event.discord_event_participations.count

    details = "**#{event.title}**\n\n"
    details += "#{event.description}\n\n" if event.description.present?
    details += I18n.t(
      "discord.webhooks.legacy_event_details.scheduled_block",
      date_stamp: "<t:#{event.scheduled_at.to_i}:D>",
      time_stamp: "<t:#{event.scheduled_at.to_i}:t>"
    )
    if event.duration
      details += I18n.t("discord.webhooks.legacy_event_details.duration_line", minutes: event.duration)
    end
    if event.respond_to?(:location) && event.location.present?
      details += I18n.t("discord.webhooks.legacy_event_details.location_line", value: event.location)
    end
    if event.respond_to?(:squad_leader) && event.squad_leader.present?
      details += I18n.t("discord.webhooks.legacy_event_details.squad_leader_line", value: event.squad_leader)
    end
    details += I18n.t("discord.webhooks.legacy_event_details.participants_line", count: participants_count)

    render json: {
      type: 4,
      data: { content: details, flags: 64 } # EPHEMERAL
    }, status: 200
  end

  def handle_modal_submit(interaction)
    custom_id = interaction["data"]["custom_id"]
    render json: { type: 4, data: { content: I18n.t("discord.webhooks.unknown_modal"), flags: 64 } }, status: 200
  end

  def handle_application_command(interaction)
    data         = interaction["data"]
    command_name = data["name"]
    member       = interaction["member"]

    case command_name
    # ------------------------------------------------------------------
    # Legacy commands (inline handlers, unchanged)
    # ------------------------------------------------------------------
    when "signup"
      handle_signup_command(interaction, member)
    when "gear"
      handle_gear_command(interaction, member)

    # ------------------------------------------------------------------
    # Phase 1 — Core member interaction commands
    # ------------------------------------------------------------------
    when "poll"
      result = DiscordPollCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "loot"
      result = DiscordLootCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "event"
      result = DiscordEventCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "invite"
      result = DiscordInviteCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    # ------------------------------------------------------------------
    # Phase 2 — Guild management commands
    # ------------------------------------------------------------------
    when "member"
      result = DiscordMemberCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "guild"
      result = DiscordGuildCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "application"
      result = DiscordApplicationCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    # ------------------------------------------------------------------
    # Phase 3 — Content and utility commands
    # ------------------------------------------------------------------
    when "docs"
      result = DiscordDocsCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "leaderboard"
      result = DiscordLeaderboardCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "activity"
      result = DiscordActivityCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "profile"
      result = DiscordProfileCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "help"
      result = DiscordHelpCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    when "alliance"
      result = DiscordAllianceCommandService.handle(interaction)
      render json: result, status: 200, content_type: "application/json"

    else
      render json: {
        type: 4,
        data: { content: I18n.t("discord.commands.errors.not_implemented"), flags: 64 }
      }, status: 200
    end
  end

  def handle_signup_command(interaction, member)
    data = interaction["data"]
    options = data["options"] || []

    role_option = options.find { |opt| opt["name"] == "role" }
    event_option = options.find { |opt| opt["name"] == "event" }

    unless role_option
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.signup_usage"), flags: 64 }
      }, status: 200
    end

    role = role_option["value"]

    # If event_id is provided, use it; otherwise try to find from message context
    if event_option
      event_id = event_option["value"].to_i
    else
      # Try to extract from message if command was used in reply to event message
      message_id = interaction.dig("message", "id")
      if message_id
        discord_event = DiscordEvent.find_by(discord_message_id: message_id)
        event_id = discord_event&.id
      end
    end

    unless event_id
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.signup_event_not_found"), flags: 64 }
      }, status: 200
    end

    handle_discord_event_signup(interaction, event_id, role, member)
  end

  def handle_gear_command(interaction, member)
    # Validate interaction structure
    data = interaction["data"]
    unless data
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.invalid_command_structure"), flags: 64 }
      }, status: 200, content_type: "application/json"
    end
    
    options = data["options"] || []
    
    # Find the subcommand option (type 1 = SUB_COMMAND)
    subcommand_option = options.find { |opt| opt["type"] == 1 }
    subcommand_name = subcommand_option&.dig("name")&.to_sym || :upload
    
    # For long-running operations (upload), defer response immediately
    if subcommand_name == :upload
      interaction_token = interaction["token"]
      unless interaction_token
        return render json: {
          type: 4,
          data: { content: I18n.t("discord.webhooks.missing_interaction_token"), flags: 64 }
        }, status: 200, content_type: "application/json"
      end
      
      render json: { type: 5 }, status: 200, content_type: "application/json" # DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE
      # Process in background
      run_async_with_db_connection do
        begin
          result = DiscordGearService.handle_upload_command(interaction)
          if result && result[:data] && result[:data][:content]
            ephemeral = result[:data][:flags] == 64
            send_followup_message(interaction_token, result[:data][:content], ephemeral: ephemeral)
          else
            send_followup_message(interaction_token, I18n.t("discord.webhooks.gear_upload_error"), ephemeral: true)
          end
        rescue => e
          discord_logger.error "Gear upload error: #{e.class.name}: #{e.message}"
          discord_logger.error e.backtrace.first(10).join("\n")
          send_followup_message(interaction_token, I18n.t("discord.webhooks.gear_upload_error"), ephemeral: true)
        end
      end
      return
    end
    
    # For quick operations, respond immediately
    begin
      case subcommand_name
      when :my
        result = DiscordGearService.handle_my_command(interaction)
      when :request
        result = DiscordGearService.handle_request_command(interaction)
      when :request_missing
        result = DiscordGearService.handle_request_missing_command(interaction)
      else
        result = {
          type: 4,
          data: { content: I18n.t("discord.webhooks.unknown_gear_subcommand"), flags: 64 }
        }
      end
      
      # Validate result structure
      unless result && result[:type] && result[:data]
        result = {
          type: 4,
          data: { content: I18n.t("discord.webhooks.gear_command_error"), flags: 64 }
        }
      end
      
      render json: result, status: 200, content_type: "application/json"
    rescue => e
      discord_logger.error "Gear command error: #{e.class.name}: #{e.message}"
      discord_logger.error e.backtrace.first(10).join("\n")
      render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.gear_command_error"), flags: 64 }
      }, status: 200, content_type: "application/json"
    end
  end

  def handle_status_update(interaction, event_id, role, status, user_id, member)
    # CRITICAL: Send deferred response IMMEDIATELY - no logging before this
    # Discord requires response within 3 seconds - any delay = "Interaction failed"

    # Store variables for background processing BEFORE render
    interaction_token = interaction["token"]
    status_value = status
    role_value = role
    event_id_value = event_id
    discord_user_id_value = member["user"]["id"]
    discord_display_name_value = discord_member_display_name(member)
    discord_login_value = DiscordGuildMemberLabel.username_with_optional_discriminator(member["user"] || {}) ||
                          discord_user_id_value.to_s

    # Start background processing thread FIRST (runs in background)
    # Response is sent AFTER thread starts to ensure immediate acknowledgment
    run_async_with_db_connection do
      begin
        # All logging happens in the background thread to avoid delays
        discord_logger.info "handle_status_update: event_id=#{event_id_value}, role=#{role_value}, status=#{status_value}, user_id=#{discord_user_id_value}"

        discord_event = DiscordEvent.find_by(id: event_id_value)
        unless discord_event
          send_followup_message(interaction_token, I18n.t("discord.webhooks.event_not_found"))
          next
        end

        unless can_rsvp_guild_event?(discord_event, discord_user_id_value)
          send_followup_message(interaction_token, account_or_membership_required_message)
          next
        end

        # Handle remove action
        if status_value == "remove"
          signup = discord_event.discord_event_signups.find_by(discord_user_id: discord_user_id_value)
          if signup
            signup.destroy
            send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.removed_from_signup"))
            update_event_message_embed(discord_event)
          else
            send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.signup_not_found"))
          end
          next
        end

        # Validate status (only on_time, late, absent - no tentative)
        valid_statuses = %w[on_time late absent]
        unless valid_statuses.include?(status_value)
          send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.invalid_status_hint"))
          next
        end

        # Find or initialize signup (one per user per event)
        signup = discord_event.discord_event_signups.find_or_initialize_by(
          discord_user_id: discord_user_id_value
        )

        # Update role and status
        # Only save role if attendance is on_time (for role sections)
        signup.role = role_value if status_value == "on_time"
        signup.status = status_value
        signup.discord_username = discord_login_value
        signup.discord_display_name = discord_display_name_value
        signup.save!

        discord_logger.info "Status updated: role=#{role_value}, status=#{status_value}"

        # Confirm to user
        status_label = discord_rsvp_status_label(status_value)
        send_followup_message(
          interaction_token,
          I18n.t("discord.webhooks.rsvp.status_updated", role: role_value.upcase, status: status_label)
        )

        # Update message embed (validation happens inside the method)
        update_event_message_embed(discord_event)
      rescue ActiveRecord::RecordInvalid => e
        discord_logger.error "Record validation error: #{e.message}"
        discord_logger.error e.record.errors.full_messages.inspect
        send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.followup_error", message: e.message))
      rescue => e
        discord_logger.error "Status update error: #{e.message}"
        discord_logger.error e.backtrace.first(5).join("\n") if Rails.env.development?
        send_followup_message(interaction_token, I18n.t("discord.webhooks.rsvp.try_again_short"))
      end
    end

    # Send deferred response IMMEDIATELY - render and return to force immediate response
    # This MUST be after Thread.new to ensure thread starts before response
    render json: { type: 5 }, status: 200, content_type: "application/json"
  end

  def handle_async_component_interaction(interaction, custom_id)
    interaction_token = interaction["token"]
    application_id = interaction["application_id"] || ENV["DISCORD_CLIENT_ID"]

    unless interaction_token.present? && application_id.present?
      return render json: {
        type: 4,
        data: { content: I18n.t("discord.webhooks.missing_token_or_application_id"), flags: 64 }
      }, status: 200
    end

    # Acknowledge quickly; process poll/loot workflows asynchronously.
    render json: { type: 5 }, status: 200, content_type: "application/json"

    if Rails.env.development? || Rails.env.test?
      DiscordInteractionJob.perform_now(custom_id, interaction_token, application_id, interaction)
    else
      DiscordInteractionJob.perform_later(custom_id, interaction_token, application_id, interaction)
    end
  rescue => e
    discord_logger.error "Async component dispatch error: #{e.class.name}: #{e.message}"
    render json: {
      type: 4,
      data: { content: I18n.t("discord.webhooks.request_processing_error"), flags: 64 }
    }, status: 200
  end

  def discord_member_display_name(member)
    DiscordGuildMemberLabel.from_member_json(member) ||
      DiscordGuildMemberLabel.from_user_json(member["user"]) ||
      member.dig("user", "username").to_s.presence ||
      I18n.t("discord.webhooks.fallback_member_name")
  end

  def discord_rsvp_status_label(status)
    I18n.t("discord.webhooks.rsvp.status_labels.#{status}", default: status.to_s.humanize)
  end

  def can_rsvp_guild_event?(discord_event, discord_user_id)
    user_link = UserDiscordConnection.find_by(discord_user_id: discord_user_id.to_s)
    return false unless user_link&.user

    GuildMember.where(guild_id: discord_event.guild_id, user_id: user_link.user_id, status: :active).exists?
  end

  def can_rsvp_alliance_event?(alliance_event, discord_user_id)
    user_link = UserDiscordConnection.find_by(discord_user_id: discord_user_id.to_s)
    return false unless user_link&.user

    alliance_event.alliance.alliance_members.where(user_id: user_link.user_id, status: :active).exists?
  end

  def account_or_membership_required_message
    I18n.t(
      "discord.interactions.account_or_membership_required",
      default: "Please create a GuildSync account at https://guild-sync.net or make sure you've joined this Alliance and/or Guild."
    )
  end

  # In test, run inline to avoid leaked background threads deadlocking transactional fixtures.
  def run_async_with_db_connection(&block)
    if Rails.env.test?
      ActiveRecord::Base.connection_pool.with_connection { block.call }
    else
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { block.call }
      end
    end
  end
end
