require "csv"

class GuildsController < ApplicationController
  include RequiresActiveGuildAccess
  include UiPagination

  GAMES_SECTION_ANCHOR = "guild-games-section"

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild, only: [ :show, :settings, :update, :archive, :members, :review_applications, :invite_members, :create_invite_link, :schedule_events, :members_gear, :member_stats, :update_member_stats_fields, :connect_discord, :update_discord_channels, :kick_member, :bulk_kick_members, :update_member_role, :bulk_update_member_roles, :search_users, :invite_user, :update_games, :create_member_tag, :assign_member_tag, :remove_member_tag ]
  before_action :require_active_guild_access, only: [ :show, :settings, :update, :members, :review_applications, :invite_members, :create_invite_link, :schedule_events, :members_gear, :member_stats, :update_member_stats_fields, :connect_discord, :update_discord_channels, :kick_member, :bulk_kick_members, :update_member_role, :bulk_update_member_roles, :search_users, :invite_user, :update_games, :create_member_tag, :assign_member_tag, :remove_member_tag ]
  before_action :block_member_access_to_owner_features, only: [ :settings, :archive, :members, :review_applications, :invite_members, :create_invite_link, :schedule_events, :connect_discord, :update_discord_channels ]
  before_action :ensure_can_view_gear_for_guild, only: [ :members_gear, :member_stats, :update_member_stats_fields ]

  def index
    preserve_session
    @guilds = current_user.guilds.includes(:owner, :guild_members)
  end

  def new
    preserve_session
    @guild = Guild.new
  end

  def create
    preserve_session
    @guild = current_user.owned_guilds.build(guild_params)
    @guild.owner = current_user

    # Handle game selection (from nested params)
    game_ids = params[:guild][:game_ids]&.reject(&:blank?) || []
    primary_game_id = params[:guild][:primary_game_id]

    # Validate at least one game before saving
    if game_ids.empty?
      @guild.errors.add(:base, t('controllers.guilds.games.at_least_one'))
      flash.now[:alert] = t('controllers.guilds.create.select_game')
      render :new, status: :unprocessable_entity
      return
    end

    # Validate primary game is selected
    unless primary_game_id.present? && game_ids.include?(primary_game_id)
      @guild.errors.add(:base, t('controllers.guilds.games.select_primary'))
      flash.now[:alert] = t('controllers.guilds.create.select_primary_game')
      render :new, status: :unprocessable_entity
      return
    end

    # Validate all game IDs exist
    invalid_game_ids = game_ids.reject { |id| Game.exists?(id: id) }
    if invalid_game_ids.any?
      @guild.errors.add(:base, "Invalid game IDs: #{invalid_game_ids.join(', ')}")
      flash.now[:alert] = t('controllers.guilds.create.invalid_games')
      render :new, status: :unprocessable_entity
      return
    end

    if @guild.save
      # Track which games are newly selected (for notification purposes)
      # Only notify for games that are pending (never activated), not deactivated games
      newly_selected_pending_games = []

      # Clear any existing game associations (in case factory created some)
      @guild.guild_games.destroy_all

      # Create guild_game associations and add owner as member in a transaction
      # This ensures atomicity - if member creation fails, rollback everything
      begin
        ActiveRecord::Base.transaction do
          game_ids.each do |game_id|
            game = Game.find(game_id)
            # Check if game is pending (never activated) and was just selected by a user
            if game.pending?
              newly_selected_pending_games << game
            end

            is_primary = (game_id == primary_game_id)
            @guild.guild_games.create!(
              game_id: game_id,
              primary: is_primary
            )
          end

          # Add owner as a member with owner role (inside transaction)
          # Check if member already exists (shouldn't happen, but safety check)
          unless @guild.guild_members.exists?(user_id: current_user.id)
            member = @guild.guild_members.build(user: current_user, role: "owner", status: "active")
            unless member.save
              raise ActiveRecord::RecordInvalid.new(member)
            end
          end
        end

        # Verify member was created successfully
        unless @guild.guild_members.exists?(user_id: current_user.id, status: :active)
          raise "Failed to create guild member - member not found after creation"
        end

        # Notify admins about any newly selected pending games (never activated)
        newly_selected_pending_games.each do |game|
          NotifyAdminsGameActivationRequestJob.perform_later(game.id, current_user.id)
        end

        GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "guild_created", description: "Created guild \"#{@guild.name}\"")
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), notice: t('controllers.guilds.create.success')
      rescue => e
        Rails.logger.error "Failed to create guild associations: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        @guild.destroy # Clean up the guild if associations failed
        flash.now[:alert] = t('controllers.guilds.create.failed', error: e.message)
        render :new, status: :unprocessable_entity
      end
    else
      # Set flash message for validation errors, especially business logic errors like subscription limits
      flash.now[:alert] = @guild.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    preserve_session
    # Guild dashboard
  end

  def settings
    preserve_session
    # Permission check is handled by block_member_access_to_owner_features for settings
    # This check is redundant but kept for safety
    unless @guild && can_manage_guild_settings?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.settings_denied')
      return
    end

    load_available_games
    @discord_setting = @guild.guild_discord_setting
    @channels = []
    @discord_guild_id = @discord_setting&.discord_guild_id
    # Always load synced roles if Discord is connected (even if empty, so the section shows)
    @synced_roles = @discord_setting&.connected? ? @guild.discord_role_syncs.order(:role_name) : []

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

    # Load channels if bot is connected (prefer this guild's connected bot token)
    if @bot_connected
      begin
        bot_token = @discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
        discord_service = DiscordService.new(bot_token: bot_token)
        channels = discord_service.get_guild_channels(@discord_guild_id)
        # Only show text channels (type 0) and forum channels (type 15)
        @channels = channels.select { |c| [ 0, 15 ].include?(c["type"]) }
      rescue => e
        Rails.logger.error "Failed to load Discord channels: #{e.message}"
        @channels = []
        @channel_error = "Failed to load channels: #{e.message}"
      end
    end

    @react_roles = @guild.react_roles.ordered
  end

  def update
    preserve_session
    unless @guild && can_manage_guild_settings?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.settings_denied')
      return
    end

    # Handle logo deletion
    if params[:commit] == "Delete Logo"
      if @guild.logo.attached?
        @guild.logo.purge
        session.save if session.respond_to?(:save)
        redirect_to guild_settings_path(@guild), notice: t('controllers.guilds.logo.deleted')
      else
        session.save if session.respond_to?(:save)
        redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.logo.no_logo')
      end
      return
    end

    # Check if this is a logo upload attempt
    if params[:commit] == "Save Logo" || params[:commit] == "Update Logo"
      # Validate that a file was selected for new uploads
      if params[:commit] == "Save Logo" && (params[:guild].blank? || params[:guild][:logo].blank?)
        session.save if session.respond_to?(:save)
        redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.update.select_photo')
        return
      end
    end

    # Only proceed if guild params are present
    if params[:guild].blank?
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.update.no_changes')
      return
    end

    # For message updates, allow empty values (they'll use defaults)
    if params[:commit] == "Save Messages"
      # Allow accept_message and reject_message to be blank (will use defaults)
    end

    # Prevent users from modifying their own role's permissions
    if params[:commit] == "Save Permissions" && @guild.owner_id != current_user.id
      guild_member = @guild.guild_members.find_by(user: current_user, status: :active)
      user_role_id = guild_member&.discord_role_id

      if user_role_id.present?
        # Check both current and new permission role IDs
        current_permission_role_ids = [
          @guild.permission_role_1_id,
          @guild.permission_role_2_id,
          @guild.permission_role_3_id,
          @guild.permission_role_4_id
        ].compact

        new_permission_role_ids = [
          params[:guild][:permission_role_1_id],
          params[:guild][:permission_role_2_id],
          params[:guild][:permission_role_3_id],
          params[:guild][:permission_role_4_id]
        ].compact

        # Check if user's role is in either current or new permission roles
        if current_permission_role_ids.include?(user_role_id) || new_permission_role_ids.include?(user_role_id)
          session.save if session.respond_to?(:save)
          redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.update.own_role_modify')
          return
        end
      end
    end

    # `publicly_listed` is governed by the same can_manage_guild_settings? guard as all other
    # guild-wide settings (application messages, role permissions, etc.). This is intentional:
    # any member with the "Manage Guild Settings" permission role may toggle visibility,
    # consistent with the existing permission model.
    if @guild.update(guild_params)
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "guild_updated", description: "Updated guild settings", title: @guild.name)
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), notice: t('controllers.guilds.update.success')
    else
      session.save if session.respond_to?(:save)
      duplicate_role_error = @guild.errors.details[:base].any? { |detail| detail[:error] == :duplicate_permission_role }
      alert_message = if duplicate_role_error
        t('controllers.guilds.update.duplicate_permission_role')
      else
        t('controllers.guilds.update.failed', errors: @guild.errors.full_messages.join(', '))
      end
      redirect_to guild_settings_path(@guild), alert: alert_message
    end
  end

  def archive
    preserve_session

    confirmation_name = params[:guild_name_confirmation].to_s.strip
    if confirmation_name != @guild.name
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), alert: t("guild_archives.alerts.name_confirmation_mismatch")
      return
    end

    @guild.archive!(actor: current_user)
    session.save if session.respond_to?(:save)
    redirect_to guild_archives_path, notice: t("guild_archives.alerts.archived_success", guild_name: @guild.name)
  rescue ArgumentError => e
    session.save if session.respond_to?(:save)
    redirect_to guild_settings_path(@guild), alert: e.message
  end

  def members
    preserve_session
    members_scope = @guild.guild_members.includes(:user, :guild_member_tags, guild_tags: [])
    @synced_roles = @guild.discord_role_syncs.order(:role_name) if @guild.guild_discord_setting&.connected?
    @guild_tags = @guild.guild_tags.order(:name)
    @can_manage_member_tags = can_manage_tags?(@guild)
    @selected_tag_id = params[:tag_id].presence

    if @selected_tag_id == "untagged"
      members_scope = members_scope.left_outer_joins(:guild_member_tags).where(guild_member_tags: { id: nil })
    elsif @selected_tag_id.present?
      selected_tag = @guild.guild_tags.find_by(id: @selected_tag_id)
      members_scope = members_scope.joins(:guild_member_tags).where(guild_member_tags: { guild_tag_id: selected_tag.id }).distinct if selected_tag
    end

    ordered_members = members_scope.order(:created_at, :id)
    @members_for_csv = ordered_members
    @members, @members_pagination = ui_paginate(ordered_members, per_page: 25, max_per_page: 100)

    respond_to do |format|
      format.html
      format.csv do
        unless can_export_members_csv?(@guild)
          redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.permissions.export_members_csv_denied", default: "You do not have permission to export members CSV.")
          return
        end
        send_data generate_members_csv(@members_for_csv), filename: "guild-#{@guild.id}-members-#{Date.current}.csv", type: "text/csv"
      end
    end
  end

  def create_member_tag
    unless can_manage_tags?(@guild)
      redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.permissions.tags_denied", default: "You do not have permission to manage tags.")
      return
    end

    tag = @guild.guild_tags.build(name: params[:name].to_s.strip, color: params[:color].to_s.strip, created_by: current_user)
    if tag.save
      redirect_to guild_members_list_path(@guild), notice: t("controllers.guilds.members.tags.created", default: "Guild tag created.")
    else
      redirect_to guild_members_list_path(@guild), alert: tag.errors.full_messages.to_sentence
    end
  end

  def assign_member_tag
    unless can_manage_tags?(@guild)
      redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.permissions.tags_denied", default: "You do not have permission to manage tags.")
      return
    end

    member = @guild.guild_members.find(params[:member_id])
    tag = @guild.guild_tags.find(params[:tag_id])
    member.guild_member_tags.find_or_create_by!(guild_tag: tag) { |gmt| gmt.assigned_by = current_user }
    redirect_to guild_members_list_path(@guild), notice: t("controllers.guilds.members.tags.assigned", default: "Tag assigned.")
  rescue ActiveRecord::RecordNotFound
    redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.members.tags.not_found", default: "Tag or member not found.")
  end

  def remove_member_tag
    unless can_manage_tags?(@guild)
      redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.permissions.tags_denied", default: "You do not have permission to manage tags.")
      return
    end

    member = @guild.guild_members.find(params[:member_id])
    tag = @guild.guild_tags.find(params[:tag_id])
    member.guild_member_tags.where(guild_tag: tag).destroy_all
    redirect_to guild_members_list_path(@guild), notice: t("controllers.guilds.members.tags.removed", default: "Tag removed.")
  rescue ActiveRecord::RecordNotFound
    redirect_to guild_members_list_path(@guild), alert: t("controllers.guilds.members.tags.not_found", default: "Tag or member not found.")
  end

  def kick_member
    preserve_session
    unless @guild && can_kick_members?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to @guild ? guild_members_list_path(@guild) : my_guilds_path, alert: t('controllers.guilds.permissions.kick_denied')
      return
    end

    member = @guild.guild_members.find(params[:member_id])
    return redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.kick_owner') if member.role == "owner"

    # Prevent users from kicking members with higher authority
    if user_has_higher_authority_than?(@guild, member.user)
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.kick_higher_authority')
      return
    end

    kicked_name = member.user.username.presence || member.user.email
    member.destroy
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "member_kicked", description: "Kicked #{kicked_name} from the guild", target_name: kicked_name)
    session.save if session.respond_to?(:save)
    redirect_to guild_members_list_path(@guild), notice: t('controllers.guilds.members.kicked')
  end

  def bulk_kick_members
    preserve_session
    unless @guild && can_kick_members?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to @guild ? guild_members_list_path(@guild) : my_guilds_path, alert: t('controllers.guilds.permissions.kick_denied')
      return
    end

    member_ids = params[:member_ids] || []
    return redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.no_selected') if member_ids.empty?

    members = @guild.guild_members.where(id: member_ids).where.not(role: "owner")

    # Filter out members with higher authority
    members_to_kick = members.reject { |member| user_has_higher_authority_than?(@guild, member.user) }

    # If any members were filtered out, show an error
    if members_to_kick.length < members.length
      filtered_count = members.length - members_to_kick.length
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.bulk_kick_higher_authority', count: filtered_count)
      return
    end

    count = members_to_kick.length
    members_to_kick.each(&:destroy)
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "members_bulk_kicked", description: "Kicked #{count} member(s) from the guild")
    session.save if session.respond_to?(:save)
    redirect_to guild_members_list_path(@guild), notice: t('controllers.guilds.members.bulk_kicked', count: count)
  end

  def update_member_role
    preserve_session
    unless @guild && can_manage_roles?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to @guild ? guild_members_list_path(@guild) : my_guilds_path, alert: t('controllers.guilds.permissions.roles_denied')
      return
    end

    member = @guild.guild_members.find(params[:member_id])

    # Prevent users from updating their own role
    if member.user_id == current_user.id
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.own_role_modify')
      return
    end

    # Prevent modifying roles of users with "Manage Guild Settings" permission (only owner can)
    # Check this BEFORE higher authority check for more specific error message
    if @guild.owner_id != current_user.id && can_manage_guild_settings?(@guild, member.user)
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.settings_user_role')
      return
    end

    # Prevent users from updating roles of users with higher authority
    if user_has_higher_authority_than?(@guild, member.user)
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.higher_authority_role')
      return
    end

    new_discord_role_id = params[:discord_role_id]
    old_discord_role_id = member.discord_role_id

    # Update the database first, then sync to Discord
    update_member_discord_role_id!(member, new_discord_role_id)

    # Update Discord role if member has Discord connection and guild has Discord connected
    if @guild.guild_discord_setting&.connected? && member.user.user_discord_connection&.discord_user_id.present?
      begin
        sync_member_discord_role!(
          member: member,
          new_discord_role_id: new_discord_role_id,
          old_discord_role_id: old_discord_role_id
        )
      rescue => e
        Rails.logger.error "Failed to update Discord role: #{e.message}"
        # Continue even if Discord update fails - database is already updated
      end
    end

    target_name = member.user.username.presence || member.user.email
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "member_role_updated", description: "Updated role for #{target_name}", target_name: target_name)
    session.save if session.respond_to?(:save)
    redirect_to guild_members_list_path(@guild), notice: t('controllers.guilds.members.role_updated')
  end

  def bulk_update_member_roles
    preserve_session
    unless @guild && can_manage_roles?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to @guild ? guild_members_list_path(@guild) : my_guilds_path, alert: t('controllers.guilds.permissions.roles_denied')
      return
    end

    member_ids = Array(params[:member_ids]).reject(&:blank?)
    new_discord_role_id = params[:discord_role_id]

    if member_ids.empty?
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.no_selected')
      return
    end
    # Allow empty role_id to clear the role (selecting "None")
    # return redirect_to guild_members_list_path(@guild), alert: "Please select a role." if new_discord_role_id.blank?

    members = @guild.guild_members.where(id: member_ids).where.not(role: "owner").where.not(user_id: current_user.id)

    # Filter out members with higher authority
    members_to_update = members.reject { |member| user_has_higher_authority_than?(@guild, member.user) }

    # Filter out members with "Manage Guild Settings" permission (only owner can modify them)
    if @guild.owner_id != current_user.id
      members_to_update = members_to_update.reject { |member| can_manage_guild_settings?(@guild, member.user) }
    end

    # If any members were filtered out, show an error
    if members_to_update.length < members.length
      filtered_count = members.length - members_to_update.length
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.members.bulk_higher_authority', count: filtered_count)
      return
    end

    count = 0

    members_to_update.each do |member|
      old_discord_role_id = member.discord_role_id
      # Update Discord role if member has Discord connection and guild has Discord connected
      if @guild.guild_discord_setting&.connected? && member.user.user_discord_connection&.discord_user_id.present?
        begin
          sync_member_discord_role!(
            member: member,
            new_discord_role_id: new_discord_role_id,
            old_discord_role_id: old_discord_role_id
          )
          update_member_discord_role_id!(member, new_discord_role_id)
        rescue => e
          Rails.logger.error "Failed to update Discord role for member #{member.id}: #{e.message}"
        end
      else
        # If no Discord connection, just update the stored role ID (convert empty string to nil)
        update_member_discord_role_id!(member, new_discord_role_id)
      end

      count += 1
    end

    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "members_bulk_role_updated", description: "Updated roles for #{count} member(s)")
    session.save if session.respond_to?(:save)
    redirect_to guild_members_list_path(@guild), notice: t('controllers.guilds.members.bulk_role_updated', count: count)
  end

  def review_applications
    preserve_session
    return redirect_to my_guilds_path, alert: t('controllers.guilds.not_found') unless @guild

    unless can_manage_applications?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.applications_denied')
      return
    end

    invites_scope = @guild.guild_invites.where(dismissed: false).includes(:user, :invited_by).order(created_at: :desc)
    @guild_invites, @invites_pagination = ui_paginate(invites_scope, per_page: 15, max_per_page: 50, page_key: :invites_page)

    applications_scope = @guild.guild_applications.where(status: :pending).includes(:user).order(created_at: :desc)
    @pending_applications, @applications_pagination = ui_paginate(applications_scope, per_page: 15, max_per_page: 50, page_key: :apps_page)
  end

  def invite_members
    preserve_session
    return redirect_to my_guilds_path, alert: t('controllers.guilds.not_found') unless @guild

    unless can_manage_applications?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.manage_members_denied')
      return
    end

    applications_scope = @guild.guild_applications.where(status: :pending).includes(:user).order(created_at: :desc)
    @pending_applications, @applications_pagination = ui_paginate(applications_scope, per_page: 15, max_per_page: 50, page_key: :apps_page)
  end

  def create_invite_link
    preserve_session
    return redirect_to my_guilds_path, alert: t('controllers.guilds.not_found') unless @guild
    unless can_manage_applications?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.manage_members_denied')
      return
    end
    if @guild.invite_links_at_capacity?
      redirect_to guild_invite_members_path(@guild), alert: t("join.invite_links_limit", count: Guild::MAX_ACTIVE_INVITE_LINKS)
      return
    end

    link = @guild.guild_invite_links.create!(created_by: current_user)
    flash[:invite_link_url] = join_guild_url(link.token)
    redirect_to guild_invite_members_path(@guild), notice: t('join.invite_link_section')
  end

  def schedule_events
    preserve_session
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

    # Only load events if bot is connected
    if @user_conn&.access_token.present? && @discord_guild_id.present? && @bot_connected
      @discord_events = @guild.discord_events.order(scheduled_at: :desc).limit(10)
    end
  end

  def members_gear
    preserve_session

    unless guild_ai_stat_scanner_entitled?(@guild)
      redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
      return
    end

    if params[:gear_upload_success].present?
      query = request.query_parameters.except("gear_upload_success")
      redirect_to guild_members_gear_path(@guild, query),
        notice: t("guilds.members_gear.upload_success_notice")
      return
    end

    @my_pending_gear_request = GearUploadRequest
      .pending_for_user(@guild, current_user)
      .includes(:requester)
      .first

    # Handle case where guild has no games (shouldn't happen, but safety check)
    if @guild.games.empty?
      @members_with_gear = []
      @gear_stats = {
        total_members: @guild.members.count,
        missing: 0,
        outdated: 0,
        up_to_date: 0,
        pending_requests: 0
      }
      @members_with_pending_requests = []
      @current_user_snapshot = nil
      return
    end

    # Get all members with their latest snapshots
    # @guild.members returns User objects (through has_many :members, through: :guild_members)
    members = @guild.members

    # Handle empty members list
    if members.empty?
      @members_with_gear = []
      @gear_stats = {
        total_members: 0,
        missing: 0,
        outdated: 0,
        up_to_date: 0,
        pending_requests: GearUploadRequest.where(guild: @guild, status: :pending).count
      }
      @members_with_pending_requests = []
      @current_user_snapshot = nil
      return
    end

    # Build member data with latest snapshot (any game — stat scanner is UI-agnostic)
    members_gear_unfiltered = members.map do |member|
      snapshot = GearSnapshot
        .where(guild: @guild, user: member)
        .order(created_at: :desc)
        .first

      status = if snapshot.nil?
        "missing"
      elsif snapshot.outdated?
        "outdated"
      else
        "up_to_date"
      end

      {
        member: member,
        snapshot: snapshot,
        status: status,
        last_updated: snapshot&.last_activity_at,
        key_stats: snapshot&.key_stats || {}
      }
    end

    @gear_stats = {
      total_members: @guild.members.count,
      missing: members_gear_unfiltered.count { |m| m[:status] == "missing" },
      outdated: members_gear_unfiltered.count { |m| m[:status] == "outdated" },
      up_to_date: members_gear_unfiltered.count { |m| m[:status] == "up_to_date" },
      pending_requests: GearUploadRequest.where(guild: @guild, status: :pending).count
    }

    snapshots_for_preload = members_gear_unfiltered.filter_map { |m| m[:snapshot] }
    if snapshots_for_preload.any?
      ActiveRecord::Associations::Preloader.new(
        records: snapshots_for_preload,
        associations: { screenshot_attachment: :blob }
      ).call
    end

    @status_filter = params[:status] # 'all', 'missing', 'outdated', 'up_to_date'

    @members_with_gear = if @status_filter.present? && @status_filter != "all"
      members_gear_unfiltered.select { |m| m[:status] == @status_filter }
    else
      members_gear_unfiltered
    end

    @current_user_snapshot = GearSnapshot
      .where(guild: @guild, user: current_user)
      .order(created_at: :desc)
      .first

    # Get members with pending requests (for display)
    pending_request_user_ids = GearUploadRequest
      .where(guild: @guild, status: :pending)
      .pluck(:target_user_id)
    @members_with_pending_requests = User.where(id: pending_request_user_ids)
  end

  def member_stats
    preserve_session

    unless guild_ai_stat_scanner_entitled?(@guild)
      redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
      return
    end

    @target_user = @guild.members.find_by(id: params[:user_id])
    unless @target_user
      redirect_to guild_members_gear_path(@guild), alert: t("guilds.member_stats.member_not_found")
      return
    end

    unless can_view_member_gear_stats?(@guild, @target_user)
      redirect_to guild_members_gear_path(@guild), alert: t("guilds.member_stats.cannot_view_other_member_stats")
      return
    end

    @snapshot = GearSnapshot
      .where(guild: @guild, user: @target_user)
      .order(created_at: :desc)
      .first
    @stat_rows = @snapshot ? @snapshot.stat_rows : []
  end

  def update_member_stats_fields
    preserve_session

    unless guild_ai_stat_scanner_entitled?(@guild)
      render json: { ok: false, error: "forbidden" }, status: :forbidden
      return
    end

    unless request.media_type&.to_s&.include?("application/json")
      head :unsupported_media_type
      return
    end

    @target_user = @guild.members.find_by(id: params[:user_id])
    unless @target_user
      render json: { ok: false, error: "not_found" }, status: :not_found
      return
    end

    unless can_edit_member_snapshot_data?(@guild, @target_user)
      render json: {
        ok: false,
        error: "forbidden",
        message: I18n.t("guilds.member_stats.cannot_edit_scanned_stats")
      }, status: :forbidden
      return
    end

    @snapshot = GearSnapshot.where(guild: @guild, user: @target_user).order(created_at: :desc).first
    unless @snapshot
      render json: { ok: false, error: "not_found" }, status: :not_found
      return
    end

    op = params[:op].to_s
    stat_key = params[:stat_key].to_s
    stat_value = params[:stat_value]
    stat_label = params[:stat_label]

    result = GearSnapshots::UpdateExtractedData.call(
      snapshot: @snapshot,
      operation: op,
      stat_key: stat_key,
      stat_value: stat_value,
      stat_label: stat_label
    )

    unless result.success?
      render json: { ok: false, error: result.code.to_s }, status: :unprocessable_entity
      return
    end

    snap = result.snapshot
    count = snap.data.is_a?(Hash) ? snap.data.size : 0
    payload = {
      ok: true,
      stat_count_label: I18n.t("guilds.member_stats.stat_count", count: count),
      remaining_count: count
    }
    if result.new_stat_key.present?
      nk = result.new_stat_key
      row = StatScanner::StatRows.from_data(snap.data).find { |r| r.key == nk }
      raw_val = snap.data.is_a?(Hash) ? snap.data[nk] : nil
      payload[:stat_key] = nk
      payload[:display_label] = row&.label
      payload[:display_value] = row&.value
      payload[:stat_json] = raw_val
    end
    render json: payload
  end

  def update_games
    preserve_session

    unless can_manage_guild_settings?(@guild)
      redirect_to @guild, alert: t('controllers.guilds.permissions.games_denied')
      return
    end

    @attempted_game_ids   = (params[:game_ids] || []).reject(&:blank?).map(&:to_s)
    @attempted_primary_id = params[:primary_game_id].to_s
    load_available_games

    validation_message = games_validation_error_message(@attempted_game_ids, @attempted_primary_id)
    if validation_message
      respond_with_games_form(:alert, validation_message)
      return
    end

    apply_guild_games!(@attempted_game_ids, @attempted_primary_id)
    respond_with_games_form(:notice, t('controllers.guilds.games.updated'))
  rescue => e
    Rails.logger.error "Failed to update games: #{e.message}"
    respond_with_games_form(:alert, t('controllers.guilds.games.update_failed', error: e.message))
  end

  def connect_discord
    preserve_session
    return redirect_to my_guilds_path, alert: t('controllers.guilds.not_found') unless @guild

    unless can_manage_discord_channels?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t("controllers.guilds.permissions.discord_channels_denied", default: "You do not have permission to manage Discord channels.")
      return
    end

    @discord_setting = @guild.guild_discord_setting
    @channels = []

    # Load channels if Discord is connected
    if @discord_setting&.connected?
      begin
        bot_token = @discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
        discord_service = DiscordService.new(bot_token: bot_token)
        channels = discord_service.get_guild_channels(@discord_setting.discord_guild_id)
        # Only show text channels (type 0) and forum channels (type 15)
        @channels = channels.select { |c| [ 0, 15 ].include?(c["type"]) }
      rescue => e
        Rails.logger.error "Failed to load Discord channels: #{e.message}"
        @channels = []
        @channel_error = "Failed to load channels: #{e.message}"
      end
    end
  end

  def update_discord_channels
    preserve_session
    # Only guild owner can update channels
    unless @guild && can_manage_discord_channels?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t("controllers.guilds.permissions.discord_channels_denied", default: "You do not have permission to manage Discord channels.")
      return
    end

    discord_setting = @guild.guild_discord_setting

    unless discord_setting&.connected?
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.discord.not_connected')
      return
    end

    if discord_setting.update(
      events_channel_id: params[:events_channel_id],
      gear_channel_id: params[:gear_channel_id],
      polls_channel_id: params[:polls_channel_id],
      loot_rolls_channel_id: params[:loot_rolls_channel_id],
      alliance_events_channel_id: params[:alliance_events_channel_id],
      alliance_polls_channel_id: params[:alliance_polls_channel_id],
      alliance_loot_rolls_channel_id: params[:alliance_loot_rolls_channel_id],
      alliance_invites_channel_id: params[:alliance_invites_channel_id]
    )
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), notice: t('controllers.guilds.discord.channels_updated')
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_settings_path(@guild), alert: t('controllers.guilds.discord.channels_failed', errors: discord_setting.errors.full_messages.join(', '))
    end
  end

  def search
    query = sanitize_search_input(params[:q])

    base = Guild
      .discoverable_for_applications
      .joins(:owner)
      .where(
        "guilds.name ILIKE :q OR guilds.description ILIKE :q OR users.username ILIKE :q OR users.email ILIKE :q",
        q: "%#{query}%"
      )
      .order("guilds.name ASC", "guilds.id ASC")

    page = ui_page_param(:page)
    per_page = ui_per_page_param(default: 10, max: 50)
    total_count = base.count
    results = base.offset((page - 1) * per_page).limit(per_page)

    render json: {
      results: results.map { |g|
        {
          id: g.id,
          name: g.name,
          owner: g.owner.username || g.owner.email,
          description: g.description,
          logo_url: g.logo.attached? ? url_for(g.logo) : nil
        }
      },
      pagination: ui_pagination_hash(page: page, per_page: per_page, total_count: total_count)
    }
  end

  def search_users
    page = ui_page_param(:page)
    per_page = ui_per_page_param(default: 20, max: 50)
    unless @guild && can_manage_roles?(@guild)
      render json: {
        error: t("controllers.guilds.permissions.roles_denied"),
        users: [],
        pagination: ui_pagination_hash(page: 1, per_page: per_page, total_count: 0)
      }, status: :forbidden
      return
    end

    query = sanitize_search_input(params[:q])
    empty_payload = {
      users: [],
      pagination: ui_pagination_hash(page: 1, per_page: per_page, total_count: 0)
    }
    return render json: empty_payload if query.length < 1

    base = User.left_joins(:user_discord_connection)
      .where(
        "users.username ILIKE :q OR users.email ILIKE :q OR user_discord_connections.discord_username ILIKE :q",
        q: "%#{query}%"
      )
      .distinct
      .order("users.id ASC")

    total_count = base.count
    users = base.offset((page - 1) * per_page).limit(per_page)

    render json: {
      users: users.map { |u|
        {
          id: u.id,
          username: u.username,
          email: u.email,
          discord_username: u.user_discord_connection&.discord_username,
          discord_connected: u.user_discord_connection.present?
        }
      },
      pagination: ui_pagination_hash(page: page, per_page: per_page, total_count: total_count)
    }
  end

  def invite_user
    preserve_session
    unless @guild && can_manage_roles?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to @guild ? guild_members_list_path(@guild) : my_guilds_path, alert: t('controllers.guilds.permissions.invite_denied')
      return
    end

    user_id = params[:user_id]
    user = User.find_by(id: user_id)

    unless user
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.invite.user_not_found')
      return
    end

    # Check if user is already an active member (allow invites for inactive/banned members)
    if @guild.guild_members.exists?(user_id: user.id, status: :active)
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.invite.already_member')
      return
    end

    # Check if pending invite already exists
    existing_invite = @guild.guild_invites.pending.find_by(user_id: user.id)
    if existing_invite
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.invite.already_invited')
      return
    end

    # Create invite - allow re-invites even if user was previously a member or had a previous invite
    invite = @guild.guild_invites.build(
      user: user,
      invited_by: current_user,
      status: :pending,
      dismissed: false
    )

    unless invite.save
      Rails.logger.error "Failed to create invite: #{invite.errors.full_messages.join(', ')}"
      session.save if session.respond_to?(:save)
      redirect_to guild_members_list_path(@guild), alert: t('controllers.guilds.invite.failed', errors: invite.errors.full_messages.join(', '))
      return
    end

    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "member_invited", description: "Invited #{user.username.presence || user.email} to the guild", target_name: user.username.presence || user.email)
    # Send Discord DM if user has Discord connection
    if user.user_discord_connection&.discord_user_id.present?
      begin
        discord_service = DiscordService.new
        base_url = request.base_url || "http://localhost:5000"
        invite_message = "You've been invited to **#{@guild.name}**! Please login to GuildSync to accept, review, or deny this invite.\n\nVisit: #{base_url}/guild_invites/#{invite.id}"
        discord_service.send_dm(user.user_discord_connection.discord_user_id, invite_message)
      rescue => e
        Rails.logger.error "Failed to send invite DM: #{e.message}"
        # Continue even if Discord DM fails
      end
    end

    session.save if session.respond_to?(:save)
    redirect_to guild_members_list_path(@guild), notice: t('controllers.guilds.invite.success')
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def set_guild
    # Try to find the guild - check both membership and ownership
    guild_id = params[:id] || params[:guild_id]

    # First try via membership
    @guild = current_user.guilds.find_by(id: guild_id)

    # If not found, try via ownership
    @guild ||= current_user.owned_guilds.find_by(id: guild_id)

    # If still not found, try direct lookup (for cases where user is owner but not member)
    @guild ||= Guild.find_by(id: guild_id, owner_id: current_user.id)

    unless @guild
      session.save if session.respond_to?(:save)
      redirect_to my_guilds_path, alert: t('controllers.guilds.access_denied')
      nil
    end
  end

  def block_member_access_to_owner_features
    # For settings, check permissions instead of just ownership
    if action_name == "settings"
      unless @guild && can_manage_guild_settings?(@guild)
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.settings_denied')
        nil
      end
    elsif action_name == "members"
      # For members page, allow if user has role management or kick permissions
      unless @guild && (can_manage_roles?(@guild) || can_kick_members?(@guild))
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.members_page_denied')
        nil
      end
    elsif action_name == "review_applications" || action_name == "invite_members" || action_name == "create_invite_link"
      # For review applications, invite members UI, and creating shareable invite links — same as can_manage_applications?
      unless @guild && can_manage_applications?(@guild)
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.applications_denied')
        nil
      end
    elsif action_name == "members_gear"
      # All guild members can view gear (per spec)
      unless @guild && can_view_gear?(@guild)
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.member_required')
        nil
      end
    elsif action_name == "connect_discord" || action_name == "update_discord_channels"
      unless @guild && can_manage_discord_channels?(@guild)
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t("controllers.guilds.permissions.discord_channels_denied")
        nil
      end
    else
      # For other owner-only features, ensure user is the owner
      unless @guild && @guild.owner_id == current_user.id
        session.save if session.respond_to?(:save)
        redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.owner_only')
        nil
      end
    end
  end

  def ensure_can_view_gear_for_guild
    return unless @guild # Don't check if guild wasn't found

    # All guild members can view gear (per spec)
    unless can_view_gear?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.guilds.permissions.member_required')
      nil
    end
  end

  def guild_params
    permitted = params.require(:guild).permit(:name, :description, :discord_invite_url, :logo, :accept_message, :reject_message,
      :publicly_listed,
      :permission_role_1_id, :permission_role_2_id, :permission_role_3_id, :permission_role_4_id,
      :role_1_can_manage_roles, :role_1_can_manage_applications, :role_1_can_manage_guild_settings, :role_1_can_kick_members, :role_1_can_invite_alliance_guilds, :role_1_can_kick_alliance_guilds, :role_1_can_manage_tags, :role_1_can_manage_warnings, :role_1_can_manage_documents, :role_1_can_manage_files, :role_1_can_manage_events, :role_1_can_manage_polls, :role_1_can_manage_loot_rolls, :role_1_can_manage_discord_channels, :role_1_can_view_activity_feed, :role_1_can_export_members_csv, :role_1_can_use_message_center, :role_1_can_manage_gear_requests, :role_1_can_edit_gear_scanned_stats,
      :role_2_can_manage_roles, :role_2_can_manage_applications, :role_2_can_manage_guild_settings, :role_2_can_kick_members, :role_2_can_invite_alliance_guilds, :role_2_can_kick_alliance_guilds, :role_2_can_manage_tags, :role_2_can_manage_warnings, :role_2_can_manage_documents, :role_2_can_manage_files, :role_2_can_manage_events, :role_2_can_manage_polls, :role_2_can_manage_loot_rolls, :role_2_can_manage_discord_channels, :role_2_can_view_activity_feed, :role_2_can_export_members_csv, :role_2_can_use_message_center, :role_2_can_manage_gear_requests, :role_2_can_edit_gear_scanned_stats,
      :role_3_can_manage_roles, :role_3_can_manage_applications, :role_3_can_manage_guild_settings, :role_3_can_kick_members, :role_3_can_invite_alliance_guilds, :role_3_can_kick_alliance_guilds, :role_3_can_manage_tags, :role_3_can_manage_warnings, :role_3_can_manage_documents, :role_3_can_manage_files, :role_3_can_manage_events, :role_3_can_manage_polls, :role_3_can_manage_loot_rolls, :role_3_can_manage_discord_channels, :role_3_can_view_activity_feed, :role_3_can_export_members_csv, :role_3_can_use_message_center, :role_3_can_manage_gear_requests, :role_3_can_edit_gear_scanned_stats,
      :role_4_can_manage_roles, :role_4_can_manage_applications, :role_4_can_manage_guild_settings, :role_4_can_kick_members, :role_4_can_invite_alliance_guilds, :role_4_can_kick_alliance_guilds, :role_4_can_manage_tags, :role_4_can_manage_warnings, :role_4_can_manage_documents, :role_4_can_manage_files, :role_4_can_manage_events, :role_4_can_manage_polls, :role_4_can_manage_loot_rolls, :role_4_can_manage_discord_channels, :role_4_can_view_activity_feed, :role_4_can_export_members_csv, :role_4_can_use_message_center, :role_4_can_manage_gear_requests, :role_4_can_edit_gear_scanned_stats,
      :default_role_id, game_ids: [], primary_game_id: [])
    sanitize_permitted_text_fields!(permitted, [:name, :description, :accept_message, :reject_message, :discord_invite_url])
  end

  def generate_members_csv(members)
    CSV.generate(headers: true) do |csv|
      csv << [ "Username", "Email", "Role", "Status", "Discord Username", "GuildSync Username", "Tags" ]
      members.each do |member|
        discord_username = normalized_member_discord_username(member)
        csv << [
          discord_username.presence || member.user.username,
          member.user.email,
          member.role,
          member.status,
          discord_username,
          member.user.username,
          member.guild_tags.order(:name).pluck(:name).join("|")
        ]
      end
    end
  end

  def normalized_member_discord_username(member)
    raw_discord_username = member.user.user_discord_connection&.discord_username.presence || member.user.discord_username.presence
    return nil if raw_discord_username.blank?

    raw_discord_username.split("#").first.strip
  end

  def activity_label_for_tracking
    return nil unless @guild
    case action_name
    when "show" then I18n.t("dashboard.viewed_guild", name: @guild.name)
    when "members" then I18n.t("dashboard.viewed_members", name: @guild.name)
    when "invite_members" then I18n.t("dashboard.viewed_invite_members", name: @guild.name)
    when "settings" then I18n.t("dashboard.viewed_settings", name: @guild.name)
    when "review_applications" then I18n.t("dashboard.viewed_applications", name: @guild.name)
    when "schedule_events" then I18n.t("dashboard.viewed_schedule", name: @guild.name)
    when "members_gear", "member_stats" then I18n.t("dashboard.viewed_members_gear", name: @guild.name)
    else I18n.t("dashboard.viewed_guild", name: @guild.name)
    end
  end

  def activity_record_for_tracking
    @guild
  end

  def update_member_discord_role_id!(member, new_discord_role_id)
    member.update_column(:discord_role_id, new_discord_role_id.presence)
  end

  def sync_member_discord_role!(member:, new_discord_role_id:, old_discord_role_id:)
    discord_service = DiscordService.new
    discord_guild_id = @guild.guild_discord_setting.discord_guild_id
    discord_user_id = member.user.user_discord_connection.discord_user_id

    # Get current Discord member to see existing roles
    discord_member = discord_service.get_guild_member(discord_guild_id, discord_user_id)
    current_discord_roles = discord_member["roles"] || [] if discord_member

    roles_to_remove = []
    # Remove old synced role if it exists and is different from new role.
    if old_discord_role_id.present? && old_discord_role_id != new_discord_role_id && current_discord_roles.include?(old_discord_role_id)
      roles_to_remove << old_discord_role_id
    end
    # Enforce "no higher synced role than matched role".
    roles_to_remove.concat(
      higher_synced_roles_to_remove(
        guild: @guild,
        discord_service: discord_service,
        discord_guild_id: discord_guild_id,
        current_discord_roles: current_discord_roles,
        new_discord_role_id: new_discord_role_id
      )
    )
    roles_to_remove.uniq.each do |role_id|
      discord_service.remove_role_from_member(discord_guild_id, discord_user_id, role_id)
    end

    # Add new role if provided and not already present
    if new_discord_role_id.present?
      role_sync = @guild.discord_role_syncs.find_by(role_id: new_discord_role_id)
      if role_sync && !current_discord_roles.include?(new_discord_role_id)
        discord_service.add_role_to_member(discord_guild_id, discord_user_id, new_discord_role_id)
      end
    end
  end

  def higher_synced_roles_to_remove(guild:, discord_service:, discord_guild_id:, current_discord_roles:, new_discord_role_id:)
    return [] if new_discord_role_id.blank?

    synced_role_ids = guild.discord_role_syncs.pluck(:role_id)
    return [] unless synced_role_ids.include?(new_discord_role_id)

    role_positions = fetch_discord_role_positions(discord_service, discord_guild_id, synced_role_ids)
    new_role_position = role_positions[new_discord_role_id]
    return [] if new_role_position.nil?

    current_discord_roles.select do |role_id|
      next false if role_id == new_discord_role_id
      role_position = role_positions[role_id]
      role_position.present? && role_position > new_role_position
    end
  rescue => e
    Rails.logger.warn("Failed to evaluate higher Discord roles for cleanup: #{e.message}")
    []
  end

  def fetch_discord_role_positions(discord_service, discord_guild_id, synced_role_ids)
    roles = discord_service.get_guild_roles(discord_guild_id)
    positions = {}
    roles.each do |role|
      rid = role["id"].to_s
      next unless synced_role_ids.include?(rid)
      positions[rid] = role["position"].to_i
    end
    positions
  end

  # Shared by GuildsController#settings and GuildsController#update_games (the
  # latter renders the games_form partial on both turbo_stream and HTML fallbacks).
  def load_available_games
    @available_games = if admin_user?
      Game.active.order(:name)
    else
      games = Game.active.order(:name)
      games = games.guild_oriented if Game.column_names.include?("guild_oriented")
      games
    end
  end

  # Returns a translated error message when the submitted games payload is invalid,
  # otherwise nil. Keeps GuildsController#update_games linear and easy to read.
  def games_validation_error_message(game_ids, primary_game_id)
    return t('controllers.guilds.games.at_least_one') if game_ids.empty?
    return t('controllers.guilds.games.select_primary') unless primary_game_id.present? && game_ids.include?(primary_game_id)

    invalid_ids = game_ids.reject { |id| Game.exists?(id: id) }
    return t('controllers.guilds.games.invalid_games', ids: invalid_ids.join(', ')) if invalid_ids.any?

    nil
  end

  # Replaces the guild_games join rows in a single transaction and enqueues
  # admin notifications for newly selected pending games.
  def apply_guild_games!(game_ids, primary_game_id)
    previously_selected_game_ids = @guild.games.pluck(:id)
    newly_selected_pending_games = []

    ActiveRecord::Base.transaction do
      @guild.guild_games.destroy_all
      game_ids.each do |game_id|
        game = Game.find(game_id)
        if game.pending? && !previously_selected_game_ids.include?(game.id)
          newly_selected_pending_games << game
        end
        @guild.guild_games.create!(game_id: game_id, primary: (game_id == primary_game_id))
      end
    end

    newly_selected_pending_games.each do |game|
      NotifyAdminsGameActivationRequestJob.perform_later(game.id, current_user.id)
    end
  end

  # Renders the games form via Turbo Stream (in-place swap, no full reload)
  # when the request accepts turbo-stream; otherwise falls back to the HTML
  # redirect-with-anchor behaviour for no-JS / no-Turbo clients.
  def respond_with_games_form(level, message)
    @toast_type    = level
    @toast_message = message

    respond_to do |format|
      format.html do
        flash[level] = message
        redirect_to guild_settings_path(@guild, anchor: GAMES_SECTION_ANCHOR)
      end
      format.turbo_stream do
        flash.now[level] = message
        render :update_games
      end
    end
  end
end
