class DiscordInteractionJob < ApplicationJob
  queue_as :default

  def perform(custom_id, interaction_token, application_id, payload)
    return unless custom_id && interaction_token && application_id

    # Store these in payload for service methods
    payload["_interaction_token"] = interaction_token
    payload["_application_id"] = application_id

    # Handle poll vote interactions
    if custom_id&.start_with?("poll_vote_")
      handle_poll_vote(custom_id, interaction_token, application_id, payload)
      return
    end

    # Handle loot roll interactions
    if custom_id&.start_with?("loot_roll_")
      handle_loot_roll(custom_id, interaction_token, application_id, payload)
      return
    end

    if custom_id&.start_with?("alliance_poll_vote_")
      handle_alliance_poll_vote(custom_id, interaction_token, application_id, payload)
      return
    end

    if custom_id&.start_with?("alliance_loot_roll_")
      handle_alliance_loot_roll(custom_id, interaction_token, application_id, payload)
      return
    end

    # Unknown custom_id (guild_battle interactions removed)
    Rails.logger.warn "Unknown custom_id: #{custom_id}"
    DiscordApi.send_followup(application_id, interaction_token, "Unknown action.")
  end

  private

  def handle_poll_vote(custom_id, interaction_token, application_id, payload)
    begin
      # Parse custom_id: poll_vote_{poll_id}_{choice}
      parts = custom_id.split("_")
      unless parts.length >= 4
        DiscordApi.send_followup(application_id, interaction_token, "Invalid poll vote format.", flags: 64)
        return
      end

      poll_id = parts[2].to_i
      choice_str = parts[3] # yes, no, or maybe

      # Map choice string to integer
      choice_map = { "yes" => 0, "no" => 1, "maybe" => 2 }
      choice = choice_map[choice_str]
      unless choice
        DiscordApi.send_followup(application_id, interaction_token, "Invalid vote choice.", flags: 64)
        return
      end

      # Find poll
      poll = Poll.find_by(id: poll_id)
      unless poll
        DiscordApi.send_followup(application_id, interaction_token, "Poll not found.", flags: 64)
        return
      end

      discord_user_id = payload.dig("member", "user", "id") || payload.dig("user", "id")
      discord_username = payload.dig("member", "user", "username") || payload.dig("user", "username")
      unless discord_user_id
        DiscordApi.send_followup(application_id, interaction_token, "Unable to identify user.", flags: 64)
        return
      end

      handler = UnregisteredInteractionHandler.new(discord_user_id: discord_user_id, discord_username: discord_username)
      user = handler.resolve_user

      if user
        unless poll.guild.members.include?(user) || poll.guild.owner == user
          DiscordApi.send_followup(application_id, interaction_token, "You are not a member of this guild.", flags: 64)
          return
        end
      end

      unless poll.open?
        DiscordApi.send_followup(application_id, interaction_token, "This poll is closed.", flags: 64)
        return
      end

      vote = handler.find_existing_interaction(poll.poll_votes) || poll.poll_votes.new
      handler.assign_identity(vote)
      vote.choice = choice

      if vote.save
        handler.send_onboarding_dm_if_needed(context_type: "Guild", context_id: poll.guild_id) unless user

        begin
          DiscordPollService.new(poll).update_poll_message
        rescue => e
          Rails.logger.error "Failed to update Discord poll message: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        end

        begin
          PollsChannel.broadcast_to(poll, {
            type: "vote_update",
            vote_counts: poll.reload.vote_counts,
            vote_percentages: poll.vote_percentages,
            total_votes: poll.total_votes
          })
        rescue => e
          Rails.logger.error "Failed to broadcast poll update: #{e.message}"
        end

        choice_emoji = { 0 => "✅ Yes", 1 => "❌ No", 2 => "🤔 Maybe" }[choice]
        DiscordApi.send_followup(application_id, interaction_token, "Vote recorded: #{choice_emoji}", flags: 64)
      else
        DiscordApi.send_followup(application_id, interaction_token, "Failed to record vote: #{vote.errors.full_messages.join(', ')}", flags: 64)
      end
    rescue => e
      Rails.logger.error "Error handling poll vote: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      DiscordApi.send_followup(application_id, interaction_token, "An error occurred while processing your vote. Please try again.", flags: 64)
    end
  end

  def handle_loot_roll(custom_id, interaction_token, application_id, payload)
    begin
      # Parse custom_id: loot_roll_{loot_roll_id}_{action}
      # action can be "roll" or "tiebreaker"
      parts = custom_id.split("_")
      unless parts.length >= 4
        DiscordApi.send_followup(application_id, interaction_token, "Invalid loot roll format.", flags: 64)
        return
      end

      loot_roll_id = parts[2].to_i
      action = parts[3]

      # Find loot roll
      loot_roll = LootRoll.find_by(id: loot_roll_id)
      unless loot_roll
        DiscordApi.send_followup(application_id, interaction_token, "Loot roll not found.", flags: 64)
        return
      end

      # Get Discord user info
      discord_user_id = payload.dig("member", "user", "id") || payload.dig("user", "id")
      discord_username = payload.dig("member", "user", "username") || payload.dig("user", "username")
      m = payload["member"]
      discord_display_name = m.present? ? DiscordGuildMemberLabel.from_member_json(m) : DiscordGuildMemberLabel.from_user_json(payload["user"])
      member_roles = payload.dig("member", "roles") || []

      unless discord_user_id
        DiscordApi.send_followup(application_id, interaction_token, "Unable to identify user.", flags: 64)
        return
      end

      case action
      when "roll"
        handle_loot_roll_initial(loot_roll, discord_user_id, discord_username, discord_display_name, member_roles, interaction_token, application_id)
      when "tiebreaker"
        handle_loot_roll_tiebreaker(loot_roll, discord_user_id, discord_display_name, member_roles, interaction_token, application_id)
      else
        DiscordApi.send_followup(application_id, interaction_token, "Unknown action.", flags: 64)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Error creating loot roll entry: #{e.class.name}: #{e.message}"
      DiscordApi.send_followup(application_id, interaction_token, e.record.errors.full_messages.first || "Failed to record roll.", flags: 64)
    rescue => e
      Rails.logger.error "Error handling loot roll: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      DiscordApi.send_followup(application_id, interaction_token, "An error occurred while processing your roll. Please try again.", flags: 64)
    end
  end

  def handle_loot_roll_initial(loot_roll, discord_user_id, discord_username, discord_display_name, member_roles, interaction_token, application_id)
    # Check if loot roll is still open
    unless loot_roll.currently_open?
      DiscordApi.send_followup(application_id, interaction_token, "This loot roll is closed.", flags: 64)
      return
    end

    # Check if there's a tie in progress - if so, only tiebreaker button works
    if loot_roll.has_tie?
      DiscordApi.send_followup(application_id, interaction_token, "A tie-breaker is in progress. Only tied users can reroll.", flags: 64)
      return
    end

    # Check if user has already rolled (and not invalidated)
    existing_entry = loot_roll.loot_roll_entries.find_by(discord_user_id: discord_user_id.to_s, is_reroll: false)
    if existing_entry
      DiscordApi.send_followup(application_id, interaction_token, "You have already rolled.", flags: 64)
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
          DiscordApi.send_followup(application_id, interaction_token, "You don't have permission to roll. Required roles not found.", flags: 64)
          return
        end
      end
    end

    # Generate server-side random roll
    roll_value = rand(loot_roll.min_roll..loot_roll.max_roll)

    # Get user's highest role position
    discord_role_position = get_highest_role_position(loot_roll.guild, member_roles)

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
    DiscordApi.send_followup(application_id, interaction_token, "🎲 You rolled **#{roll_value}**!", flags: 64)
  end

  def handle_loot_roll_tiebreaker(loot_roll, discord_user_id, discord_display_name, member_roles, interaction_token, application_id)
    # Check if there's actually a tie
    unless loot_roll.has_tie?
      DiscordApi.send_followup(application_id, interaction_token, "No tie-breaker needed.", flags: 64)
      return
    end

    # Check if user is one of the tied users
    tied_user_ids = loot_roll.tied_user_ids
    unless tied_user_ids.include?(discord_user_id.to_s)
      DiscordApi.send_followup(application_id, interaction_token, "You are not part of the tie. Only tied users can reroll.", flags: 64)
      return
    end

    # Check if user has already rerolled for this tiebreaker round
    user_entry = loot_roll.loot_roll_entries.active.find_by(discord_user_id: discord_user_id.to_s)
    if user_entry&.tiebreaker_round.to_i >= loot_roll.current_tiebreaker_round
      DiscordApi.send_followup(application_id, interaction_token, "You have already rerolled for this tie-breaker round. Waiting for other tied users.", flags: 64)
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
    DiscordApi.send_followup(application_id, interaction_token, "🎲 Tie-breaker: You rolled **#{new_roll_value}**!", flags: 64)
  end

  def update_loot_roll_discord_and_broadcast(loot_roll)
    begin
      DiscordLootRollService.new(loot_roll).update_loot_roll_message
    rescue => e
      Rails.logger.error "Failed to update Discord loot roll message: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    begin
      LootRollsChannel.broadcast_update(loot_roll)
    rescue => e
      Rails.logger.error "Failed to broadcast loot roll update: #{e.message}"
    end
  end

  def get_highest_role_position(guild, member_role_ids)
    # Get the synced roles that match the user's roles
    synced_roles = guild.discord_role_syncs.where(role_id: member_role_ids)

    # If we can fetch role positions from Discord API, use them
    # For now, use the order of synced roles as a proxy
    # Lower number = higher priority
    return 999 if synced_roles.empty?

    # Try to get role positions from Discord API
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

      # Return the highest position (highest rank = highest position number)
      # But for tie-breaking, lower number wins, so we return negative
      user_role_positions.max || 999
    rescue => e
      Rails.logger.error "Failed to fetch role positions: #{e.message}"
      999
    end
  end

  def handle_alliance_poll_vote(custom_id, interaction_token, application_id, payload)
    rest = custom_id.delete_prefix("alliance_poll_vote_")
    poll_id_str, choice_str = rest.split("_", 2)
    poll_id = poll_id_str.to_i
    choice_map = { "yes" => 0, "no" => 1, "maybe" => 2 }
    choice = choice_map[choice_str]

    unless choice
      DiscordApi.send_followup(application_id, interaction_token, "Invalid vote choice.", flags: 64)
      return
    end

    poll = AlliancePoll.find_by(id: poll_id)
    unless poll
      DiscordApi.send_followup(application_id, interaction_token, "Poll not found.", flags: 64)
      return
    end

    discord_user_id = payload.dig("member", "user", "id") || payload.dig("user", "id")
    discord_username = payload.dig("member", "user", "username") || payload.dig("user", "username")
    unless discord_user_id
      DiscordApi.send_followup(application_id, interaction_token, "Unable to identify user.", flags: 64)
      return
    end

    handler = UnregisteredInteractionHandler.new(discord_user_id: discord_user_id, discord_username: discord_username)
    user = handler.resolve_user

    if user
      unless poll.alliance.alliance_members.where(user_id: user.id, status: :active).exists?
        DiscordApi.send_followup(application_id, interaction_token, "You are not a member of this alliance.", flags: 64)
        return
      end
    end

    unless poll.open?
      DiscordApi.send_followup(application_id, interaction_token, "This poll is closed.", flags: 64)
      return
    end

    vote = handler.find_existing_interaction(poll.alliance_poll_votes) || poll.alliance_poll_votes.new
    handler.assign_identity(vote)
    vote.choice = choice

    if vote.save
      handler.send_onboarding_dm_if_needed(context_type: "Alliance", context_id: poll.alliance_id) unless user

      begin
        DiscordAlliancePollService.update_all_linked_messages(poll.reload)
      rescue => e
        Rails.logger.error "Failed to update alliance poll Discord messages: #{e.message}"
      end

      begin
        AlliancePollsChannel.broadcast_vote_update(poll)
      rescue StandardError => e
        Rails.logger.warn "[DiscordInteractionJob] Alliance poll Action Cable broadcast failed: #{e.class}: #{e.message}"
      end

      choice_emoji = { 0 => "✅ Yes", 1 => "❌ No", 2 => "🤔 Maybe" }[choice]
      DiscordApi.send_followup(application_id, interaction_token, "Vote recorded: #{choice_emoji}", flags: 64)
    else
      DiscordApi.send_followup(application_id, interaction_token, "Failed to record vote: #{vote.errors.full_messages.join(', ')}", flags: 64)
    end
  rescue => e
    Rails.logger.error "Error handling alliance poll vote: #{e.class.name}: #{e.message}"
    DiscordApi.send_followup(application_id, interaction_token, "An error occurred while processing your vote. Please try again.", flags: 64)
  end

  def handle_alliance_loot_roll(custom_id, interaction_token, application_id, payload)
    rest = custom_id.delete_prefix("alliance_loot_roll_")
    m = rest.match(/\A(\d+)_(.+)\z/)
    unless m
      DiscordApi.send_followup(application_id, interaction_token, "Invalid loot roll format.", flags: 64)
      return
    end

    loot_roll_id = m[1].to_i
    action = m[2]
    unless action == "roll"
      DiscordApi.send_followup(application_id, interaction_token, "Unknown action.", flags: 64)
      return
    end

    loot_roll = AllianceLootRoll.find_by(id: loot_roll_id)
    unless loot_roll
      DiscordApi.send_followup(application_id, interaction_token, "Loot roll not found.", flags: 64)
      return
    end

    discord_user_id = payload.dig("member", "user", "id") || payload.dig("user", "id")
    m = payload["member"]
    discord_display_name = m.present? ? DiscordGuildMemberLabel.from_member_json(m) : DiscordGuildMemberLabel.from_user_json(payload["user"])
    discord_username = payload.dig("member", "user", "username") || payload.dig("user", "username")

    unless discord_user_id
      DiscordApi.send_followup(application_id, interaction_token, "Unable to identify user.", flags: 64)
      return
    end

    unless loot_roll.currently_open?
      DiscordApi.send_followup(application_id, interaction_token, "This loot roll is closed.", flags: 64)
      return
    end

    handler = UnregisteredInteractionHandler.new(discord_user_id: discord_user_id, discord_username: discord_username)
    user = handler.resolve_user

    if user
      unless loot_roll.alliance.alliance_members.where(user_id: user.id, status: :active).exists?
        DiscordApi.send_followup(application_id, interaction_token, "You are not a member of this alliance.", flags: 64)
        return
      end
    end

    existing = handler.find_existing_interaction(loot_roll.alliance_loot_roll_entries)
    if existing
      DiscordApi.send_followup(application_id, interaction_token, "You have already rolled.", flags: 64)
      return
    end

    entry = loot_roll.alliance_loot_roll_entries.new(
      display_name: discord_display_name.presence || (user ? DiscordGuildMemberLabel.fallback_label(user) : (discord_username || "Unknown"))
    )
    handler.assign_identity(entry)
    entry.save!

    handler.send_onboarding_dm_if_needed(context_type: "Alliance", context_id: loot_roll.alliance_id) unless user

    DiscordAllianceLootRollService.update_all_linked_messages(loot_roll.reload)
    begin
      AllianceLootRollsChannel.broadcast_update(loot_roll.reload)
    rescue StandardError => e
      Rails.logger.error "Failed to broadcast alliance loot roll update: #{e.message}"
    end
    DiscordApi.send_followup(application_id, interaction_token, "🎲 You rolled **#{entry.roll_value}**!", flags: 64)
  rescue ActiveRecord::RecordInvalid => e
    DiscordApi.send_followup(application_id, interaction_token, e.record.errors.full_messages.first || "Failed to record roll.", flags: 64)
  rescue => e
    Rails.logger.error "Error handling alliance loot roll: #{e.class.name}: #{e.message}"
    DiscordApi.send_followup(application_id, interaction_token, "An error occurred while processing your roll. Please try again.", flags: 64)
  end
end
