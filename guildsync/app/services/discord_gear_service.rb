class DiscordGearService
  class << self
    def handle_upload_command(interaction)
      # Extract image from interaction
      image_url = extract_image_url(interaction)
      
      unless image_url
        return {
          type: 4,
          data: {
            content: "Please attach an image to your command or message.",
            flags: 64
          }
        }
      end
      
      # Download image (with security validation)
      begin
        image_file = download_image(image_url)
      rescue => e
        Rails.logger.error "Failed to download image: #{e.message}"
        ErrorLogger.capture(
          e,
          context: { component: "DiscordGearService.handle_upload_command", phase: "download_image" },
          severity: "medium"
        )
        return {
          type: 4,
          data: {
            content: "Failed to download image. Please ensure the image URL is valid and accessible.",
            flags: 64
          }
        }
      end
      
      # Determine guild and user from Discord context
      # Handle missing interaction structure (e.g., DMs)
      guild_discord_id = interaction.dig('guild_id')
      user_discord_id = interaction.dig('member', 'user', 'id')
      
      unless guild_discord_id && user_discord_id
        return {
          type: 4,
          data: {
            content: "This command must be used in a server, not in DMs.",
            flags: 64
          }
        }
      end
      
      guild = find_guild_by_discord_id(guild_discord_id)
      user = find_user_by_discord_id(user_discord_id)
      
      unless guild && user
        return {
          type: 4,
          data: {
            content: "Could not find guild or user. Please ensure you're connected to the guild.",
            flags: 64
          }
        }
      end
      
      # Determine game for this upload
      # For Discord, try to infer from context or use primary game
      # Could also add game selection to Discord command in future
      game = guild.primary_game || guild.games.first
      
      unless game
        return {
          type: 4,
          data: {
            content: "Guild must be associated with at least one game. Please configure games in guild settings.",
            flags: 64
          }
        }
      end
      
      # If guild has multiple games, could prompt user to select
      # For now, use primary game or first game
      if guild.games.count > 1
        # Could add game selection to Discord command options in future
        # For now, use primary game
        game = guild.primary_game || guild.games.first
      end
      
      # Process OCR (usage limits + optional per-IP checks; Discord uses ChannelRequest for OcrRequest metadata)
      ocr_result = GearOcrService.process_image(
        image_file,
        game,
        user: user,
        request: Ocr::ChannelRequest.for_discord_gear_upload,
        guild: guild
      )
      
      unless ocr_result[:success]
        return {
          type: 4,
          data: {
            content: ocr_result[:error].presence || "Failed to process image. Please ensure it's a valid screenshot.",
            flags: 64
          }
        }
      end
      
      # Rewind file pointer before embedding generation
      image_file.rewind if image_file.respond_to?(:rewind)
      
      # Generate embedding and validate (uses game_id, not guild_id)
      # Note: This may take a few seconds - for Discord, this should be done in background
      # after deferring the response
      begin
        embedding = GearEmbeddingService.generate_embedding(image_file)
        validation_result = GearEmbeddingService.validate_embedding(embedding, game.id)
      rescue => e
        Rails.logger.error "Failed to generate embedding: #{e.message}"
        ErrorLogger.capture(
          e,
          context: {
            component: "DiscordGearService.handle_upload_command",
            phase: "embedding",
            guild_id: guild&.id,
            user_id: user&.id
          }.compact,
          severity: "medium"
        )
        # Continue without embedding - validation will fail but upload can still succeed
        embedding = nil
        validation_result = { valid: false, warning: "Could not validate image similarity. Please ensure this is a readable stats screenshot." }
      end
      
      # Ensure validation_result has required keys
      validation_result ||= { valid: false, warning: nil }
      validation_result[:valid] = validation_result[:valid] || false
      validation_result[:warning] = validation_result[:warning] || nil
      
      # Always create new snapshot (keep history)
      snapshot = GearSnapshot.new(
        guild: guild,
        user: user,
        game: game,
        source: 'discord',
        raw_text: ocr_result[:raw_text],
        data: ocr_result[:data],
        embedding: embedding&.to_json,
        validation_passed: validation_result[:valid],
        validation_warning: validation_result[:warning]
      )
      
      # Rewind file pointer before attach
      image_file.rewind if image_file.respond_to?(:rewind)
      snapshot.screenshot.attach(io: image_file, filename: "gear_#{user.id}_#{Time.current.to_i}.png")
      
      if snapshot.save
        GearStatScanActivityLog.log_successful_upload(
          guild: guild,
          initiated_by: user,
          game_name: game.name
        )

        # Mark pending requests as completed (handle errors gracefully)
        begin
          GearUploadRequest.pending_for_user(guild, user).each(&:mark_completed!)
        rescue => e
          Rails.logger.warn "Failed to mark requests as completed: #{e.message}"
          # Continue - not critical
        end
        
        # Build response summary
        summary = build_gear_summary(snapshot)
        summary_text = summary.present? ? "\n\n#{summary}" : "\n\n*No stats extracted from image.*"
        warning_text = validation_result[:warning] ? "\n\n⚠️ #{validation_result[:warning]}" : ""
        
        {
          type: 4,
          data: {
            content: "✅ Stat snapshot uploaded successfully!#{summary_text}#{warning_text}",
            flags: 0
          }
        }
      else
        error_message = snapshot.errors.full_messages.join(', ')
        {
          type: 4,
          data: {
            content: "Failed to save stat snapshot: #{error_message}",
            flags: 64
          }
        }
      end
    end
    
    def handle_my_command(interaction)
      # Handle missing interaction structure (e.g., DMs)
      guild_discord_id = interaction.dig('guild_id')
      user_discord_id = interaction.dig('member', 'user', 'id')
      
      unless guild_discord_id && user_discord_id
        return {
          type: 4,
          data: {
            content: "This command must be used in a server, not in DMs.",
            flags: 64
          }
        }
      end
      
      guild = find_guild_by_discord_id(guild_discord_id)
      user = find_user_by_discord_id(user_discord_id)
      
      unless guild && user
        return {
          type: 4,
          data: {
            content: "Could not find guild or user.",
            flags: 64
          }
        }
      end
      
      snapshot = GearSnapshot.latest_for_user(guild, user).first
      
      unless snapshot
        return {
          type: 4,
          data: {
            content: "You haven't uploaded a stat snapshot yet. Use `/gear upload` with an image.",
            flags: 64
          }
        }
      end
      
      summary = build_gear_summary(snapshot)
      summary_text = summary.present? ? summary : "*No stats available.*"
      
      {
        type: 4,
        data: {
            content: "**Your Latest Stat Snapshot**\n\n#{summary_text}\n\nLast updated: #{format_time_ago(snapshot.last_activity_at)} ago",
          flags: 0
        }
      }
    end
    
    def handle_request_command(interaction)
      # Admin only - check permissions
      # Handle missing interaction structure (e.g., DMs)
      guild_discord_id = interaction.dig('guild_id')
      requester_discord_id = interaction.dig('member', 'user', 'id')
      
      unless guild_discord_id && requester_discord_id
        return {
          type: 4,
          data: {
            content: "This command must be used in a server, not in DMs.",
            flags: 64
          }
        }
      end
      
      guild = find_guild_by_discord_id(guild_discord_id)
      requester = find_user_by_discord_id(requester_discord_id)
      
      unless guild && requester
        return {
          type: 4,
          data: {
            content: "Could not find guild or user.",
            flags: 64
          }
        }
      end
      
      # Check permissions (owner or officer)
      unless can_request_gear?(guild, requester)
        return {
          type: 4,
          data: {
            content: "You don't have permission to request stat updates.",
            flags: 64
          }
        }
      end
      
      # Extract target user from mention
      target_user_id = extract_mentioned_user(interaction)
      
      unless target_user_id
        return {
          type: 4,
          data: {
            content: "Please mention a user: `/gear request @username`",
            flags: 64
          }
        }
      end
      
      target_user = find_user_by_discord_id(target_user_id)
      
      unless target_user
        return {
          type: 4,
          data: {
            content: "Could not find mentioned user.",
            flags: 64
          }
        }
      end
      
      # Create request (handle validation errors)
      begin
        request = GearUploadRequest.create!(
          guild: guild,
          requester: requester,
          target_user: target_user,
          requested_at: Time.current
        )
      rescue ActiveRecord::RecordInvalid => e
        return {
          type: 4,
          data: {
            content: "Failed to create request: #{e.record.errors.full_messages.join(', ')}",
            flags: 64
          }
        }
      end
      
      # Send DM/mention
      DiscordGearRequestJob.perform_later(request.id)
      
      user_display_name = target_user.display_name.presence || target_user.username || "User"
      
      {
        type: 4,
        data: {
            content: "✅ Stat update requested for #{user_display_name}",
          flags: 0
        }
      }
    end
    
    def handle_request_missing_command(interaction)
      # Admin only - check permissions
      # Handle missing interaction structure (e.g., DMs)
      guild_discord_id = interaction.dig('guild_id')
      requester_discord_id = interaction.dig('member', 'user', 'id')
      
      unless guild_discord_id && requester_discord_id
        return {
          type: 4,
          data: {
            content: "This command must be used in a server, not in DMs.",
            flags: 64
          }
        }
      end
      
      guild = find_guild_by_discord_id(guild_discord_id)
      requester = find_user_by_discord_id(requester_discord_id)
      
      unless guild && requester
        return {
          type: 4,
          data: {
            content: "Could not find guild or user.",
            flags: 64
          }
        }
      end
      
      # Check permissions (owner or officer)
      unless can_request_gear?(guild, requester)
        return {
          type: 4,
          data: {
            content: "You don't have permission to request stat updates.",
            flags: 64
          }
        }
      end
      
      # Get status filter from options (optional)
      # Discord subcommand structure: options contains subcommand, subcommand has its own options
      options = interaction.dig('data', 'options') || []
      subcommand_option = options.find { |opt| opt['type'] == 1 } # SUB_COMMAND type
      subcommand_options = subcommand_option&.dig('options') || []
      status_option = subcommand_options.find { |opt| opt['name'] == 'status' }
      status_filter = status_option&.dig('value') # 'missing', 'outdated', or 'all'
      
      # Find members with missing/outdated gear
      members_to_request = []
      
      # Handle empty guild members
      if guild.members.empty?
        return {
          type: 4,
          data: {
            content: "This guild has no members.",
            flags: 64
          }
        }
      end
      
      guild.members.each do |member|
        snapshot = GearSnapshot.latest_for_user(guild, member)
        status = if snapshot.nil?
          'missing'
        elsif snapshot.outdated?
          'outdated'
        else
          'up_to_date'
        end
        
        if status_filter == 'all' && status != 'up_to_date'
          members_to_request << member
        elsif status_filter == status
          members_to_request << member
        elsif status_filter.nil? && status != 'up_to_date'
          # Default: request from both missing and outdated
          members_to_request << member
        end
      end
      
      if members_to_request.empty?
        return {
          type: 4,
          data: {
            content: "No members found with missing or outdated stats.",
            flags: 64
          }
        }
      end
      
      # Create requests and queue jobs
      count = 0
      errors = []
      
      members_to_request.each do |member|
        # Skip if there's already a pending request
        next if GearUploadRequest.pending_for_user(guild, member).exists?
        
        begin
          request = GearUploadRequest.create!(
            guild: guild,
            requester: requester,
            target_user: member,
            requested_at: Time.current
          )
          
          DiscordGearRequestJob.perform_later(request.id)
          count += 1
        rescue ActiveRecord::RecordInvalid => e
          errors << "#{member.display_name || member.username}: #{e.record.errors.full_messages.join(', ')}"
          Rails.logger.warn "Failed to create gear request for #{member.id}: #{e.message}"
        end
      end
      
      response_content = "✅ Sent stat update requests to #{count} member#{count == 1 ? '' : 's'}"
      if errors.any?
        response_content += "\n\n⚠️ Failed to create #{errors.length} request#{errors.length == 1 ? '' : 's'}: #{errors.first(3).join('; ')}"
        response_content += " (and #{errors.length - 3} more)" if errors.length > 3
      end
      
      {
        type: 4,
        data: {
          content: response_content,
          flags: 0
        }
      }
    end
    
    def handle_channel_image_message(event, guild)
      # When image is posted in configured Members Gear channel without command
      # Treat as /gear upload
      image_attachment = event.message.attachments.find { |a| a.image? }
      
      unless image_attachment
        return # No image found
      end
      
      # Validate event structure
      unless event.server && event.user
        Rails.logger.warn "Discord event missing server or user information"
        return
      end
      
      # Create fake interaction structure matching Discord's format
      fake_interaction = {
        'guild_id' => event.server.id.to_s,
        'member' => {
          'user' => {
            'id' => event.user.id.to_s
          }
        },
        'data' => {
          'resolved' => {
            'attachments' => {
              image_attachment.id.to_s => {
                'url' => image_attachment.url,
                'content_type' => image_attachment.content_type || 'image/png'
              }
            }
          }
        }
      }
      
      begin
        result = handle_upload_command(fake_interaction)
        
        # Send response as a message in the channel
        if result && result[:type] == 4 && result[:data] && result[:data][:content]
          event.respond(result[:data][:content])
        end
      rescue => e
        Rails.logger.error "Error handling channel image message: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        ErrorLogger.capture(
          e,
          context: { component: "DiscordGearService.handle_channel_image_message" },
          severity: "high"
        )
        begin
          event.respond("❌ Failed to process stat upload. Please try using `/gear upload` command instead.")
        rescue => respond_error
          Rails.logger.error "Failed to send error response: #{respond_error.message}"
        end
      end
    end
    
    private
    
    def extract_image_url(interaction)
      # Discord interaction structure:
      # interaction['data']['resolved']['attachments'] is a hash where keys are attachment IDs
      # Each attachment has: 'url', 'content_type', etc.
      attachments_hash = interaction.dig('data', 'resolved', 'attachments') || {}
      
      # Find first image attachment
      attachment = attachments_hash.values.find do |att|
        att['content_type']&.start_with?('image/') || 
        att['url']&.match?(/\.(png|jpg|jpeg|gif|webp)/i)
      end
      
      attachment&.dig('url')
    end
    
    def download_image(url)
      require 'open-uri'
      
      # Validate URL
      uri = URI.parse(url)
      unless ['http', 'https'].include?(uri.scheme)
        raise ArgumentError, "Invalid URL scheme"
      end
      
      # Validate it's a Discord CDN URL (optional but recommended)
      unless uri.host&.include?('discord') || uri.host&.include?('discordapp')
        Rails.logger.warn "Downloading image from non-Discord URL: #{url}"
      end
      
      # Set timeout and size limits
      URI.open(url, 
        read_timeout: 10,
        content_length_proc: ->(size) {
          raise ArgumentError, "File too large" if size && size > 10.megabytes
        }
      )
    end
    
    def format_time_ago(time)
      distance = Time.current - time
      case distance
      when 0..59
        "#{distance.to_i} seconds"
      when 60..3599
        "#{(distance / 60).to_i} minutes"
      when 3600..86399
        "#{(distance / 3600).to_i} hours"
      else
        "#{(distance / 86400).to_i} days"
      end
    end
    
    def find_guild_by_discord_id(discord_id)
      Guild.joins(:guild_discord_setting)
          .where(guild_discord_settings: { discord_guild_id: discord_id })
          .first
    end
    
    def find_user_by_discord_id(discord_id)
      User.joins(:user_discord_connection)
          .where(user_discord_connections: { discord_user_id: discord_id })
          .first
    end
    
    def build_gear_summary(snapshot)
      return "" unless snapshot
      
      lines = []
      key_stats = snapshot.key_stats || {}
      
      key_stats.each do |key, value|
        next if value.nil? || value.to_s.strip.empty?
        lines << "**#{key}:** #{value}"
      end
      
      lines.join("\n")
    end
    
    def can_request_gear?(guild, user)
      return true if guild.owner_id == user.id
      
      # Check custom-role permission via Discord role sync.
      guild_member = guild.guild_members.find_by(user: user, status: :active)
      return false unless guild_member

      role_id = guild_member.discord_role_id
      return false if role_id.blank?

      (guild.permission_role_1_id == role_id && guild.role_1_can_manage_gear_requests?) ||
      (guild.permission_role_2_id == role_id && guild.role_2_can_manage_gear_requests?) ||
      (guild.permission_role_3_id == role_id && guild.role_3_can_manage_gear_requests?) ||
      (guild.permission_role_4_id == role_id && guild.role_4_can_manage_gear_requests?)
    end
    
    def extract_mentioned_user(interaction)
      # Extract from options - Discord sends user option as nested in subcommand
      options = interaction.dig('data', 'options') || []
      subcommand_option = options.find { |opt| opt['type'] == 1 } # SUB_COMMAND type
      subcommand_options = subcommand_option&.dig('options') || []
      user_option = subcommand_options.find { |opt| opt['name'] == 'user' }
      user_option&.dig('value')
    end
  end
end

