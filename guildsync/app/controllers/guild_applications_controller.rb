class GuildApplicationsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild_application, only: [ :message, :accept, :reject ]

  def index
    preserve_session
    @applications = current_user.guild_applications.includes(:guild).order(created_at: :desc)
    # Show all pending invites (not dismissed) - allow re-invites even if user was previously a member
    @pending_invites = current_user.guild_invites.pending.includes(:guild, :invited_by).order(created_at: :desc)
  end

  def new
    preserve_session
    @guilds = available_guilds_by_game(current_user)
    @guild_id = params[:guild_id]
    @application = GuildApplication.new
    @application.guild_id = @guild_id if @guild_id.present?
    apply_initial_discord_username_prefill!
  end

  def create
    preserve_session

    if params[:guild_id].blank?
      @guilds = available_guilds_by_game(current_user)
      @guild_id = nil
      @application = GuildApplication.new(guild_application_params)
      flash.now[:alert] = "Please select a guild from the search results."
      render :new, status: :unprocessable_entity
      return
    end

    @guild = Guild.discoverable_for_applications.find_by(id: guild_application_params[:guild_id])
    unless @guild
      @guilds = available_guilds_by_game(current_user)
      @guild_id = guild_application_params[:guild_id]
      @application = GuildApplication.new(guild_application_params)
      flash.now[:alert] = t("guild_applications.create.guild_not_available")
      render :new, status: :unprocessable_entity
      return
    end

    # Check if user is already an active member of this guild
    if @guild.guild_members.exists?(user_id: current_user.id, status: :active)
      @guilds = available_guilds_by_game(current_user)
      @guild_id = guild_application_params[:guild_id]
      @application = GuildApplication.new(guild_application_params)
      flash.now[:alert] = "Silly goose, you are already in this guild!"
      render :new, status: :unprocessable_entity
      return
    end

    @application = current_user.guild_applications.build(
      guild: @guild,
      discord_username: guild_application_params[:discord_username],
      message: guild_application_params[:message],
      character_details: guild_application_params[:character_details],
      status: :pending
    )

    if @application.save
      session.save if session.respond_to?(:save)
      redirect_to guild_applications_path, notice: "Application submitted successfully!"
    else
      @guilds = available_guilds_by_game(current_user)
      @guild_id = guild_application_params[:guild_id]
      render :new, status: :unprocessable_entity
    end
  end

  def accept
    preserve_session

    if @guild_application.pending?
      guild = @guild_application.guild
      # Check if user is already a member, if so update their status, otherwise create new member
      guild_member = guild.guild_members.find_by(user_id: @guild_application.user.id)
      if guild_member
        # User is already a member, ensure they're active and have default role
        guild_member.update!(
          status: :active,
          discord_role_id: guild.default_role_id || guild_member.discord_role_id
        )
      else
        # User is not a member, create new membership using association method
        guild_member = guild.guild_members.create(
          user: @guild_application.user,
          role: :member,
          status: :active,
          discord_role_id: guild.default_role_id # Always set default role if configured
        )
        unless guild_member.persisted?
          session.save if session.respond_to?(:save)
          redirect_to guild_invite_members_path(@guild_application.guild), alert: guild_member.errors.full_messages.to_sentence
          return
        end
      end

      # Get applicant info once for use in both role assignment and notification
      applicant = @guild_application.user
      applicant_discord_connection = applicant.user_discord_connection

      # Apply default Discord role to Discord server if set and user has Discord connection
      if guild.default_role_id.present? && guild.guild_discord_setting&.connected? && applicant_discord_connection&.discord_user_id.present?
        begin
          discord_service = DiscordService.new
          discord_guild_id = guild.guild_discord_setting.discord_guild_id
          discord_user_id = applicant_discord_connection.discord_user_id

          # Get current Discord member to see existing roles
          discord_member = discord_service.get_guild_member(discord_guild_id, discord_user_id)
          current_discord_roles = discord_member["roles"] || [] if discord_member

          # Add default role if not already present
          if !current_discord_roles.include?(guild.default_role_id)
            discord_service.add_role_to_member(discord_guild_id, discord_user_id, guild.default_role_id)
          end
        rescue => e
          Rails.logger.error "Failed to apply default Discord role: #{e.message}"
          # Continue even if Discord role assignment fails - discord_role_id is already set above
        end
      end

      @guild_application.accepted!
      GuildActivityLogger.log(guild: guild, user: current_user, action_type: "application_accepted", description: "Accepted application from #{applicant.username.presence || applicant.email}", target_name: applicant.username.presence || applicant.email)

      # Send Discord message if applicant has Discord connection
      if applicant_discord_connection&.discord_user_id.present?
        begin
          discord_service = DiscordService.new
          accept_message = guild.accept_message.presence || I18n.t("guilds.settings.application_messages.accept_default_message", guild_name: guild.name)
          accept_message = interpolate_guild_name(accept_message, guild.name)
          content = "🎉 **Application Accepted**\n\n#{accept_message}"
          discord_service.send_dm(applicant_discord_connection.discord_user_id, content)
        rescue => e
          Rails.logger.error "Failed to send acceptance message to applicant: #{e.message}"
        end
      end

      session.save if session.respond_to?(:save)
      redirect_to guild_invite_members_path(@guild_application.guild), notice: "Member accepted and added to guild!"
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_invite_members_path(@guild_application.guild), alert: "Application is not pending."
    end
  end

  def reject
    preserve_session

    if @guild_application.pending?
      @guild_application.rejected!
      applicant = @guild_application.user
      GuildActivityLogger.log(guild: @guild_application.guild, user: current_user, action_type: "application_rejected", description: "Rejected application from #{applicant.username.presence || applicant.email}", target_name: applicant.username.presence || applicant.email)

      # Send Discord message if applicant has Discord connection
      applicant_discord_connection = applicant.user_discord_connection
      if applicant_discord_connection&.discord_user_id.present?
        begin
          discord_service = DiscordService.new
          reject_message = @guild_application.guild.reject_message.presence || I18n.t("guilds.settings.application_messages.reject_default_message")
          content = "❌ **Application Rejected**\n\n#{reject_message}"
          discord_service.send_dm(applicant_discord_connection.discord_user_id, content)
        rescue => e
          Rails.logger.error "Failed to send rejection message to applicant: #{e.message}"
        end
      end

      session.save if session.respond_to?(:save)
      redirect_to guild_invite_members_path(@guild_application.guild), notice: "Applicant rejected."
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_invite_members_path(@guild_application.guild), alert: "Application is not pending."
    end
  end

  def message
    preserve_session
    unless can_manage_applications?(@guild_application.guild)
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: "You do not have permission to access this page."
      return
    end

    applicant = @guild_application.user
    applicant_discord_connection = applicant.user_discord_connection

    if applicant_discord_connection&.discord_user_id.present?
      begin
        discord_service = DiscordService.new
        content = "💬 **Message from #{@guild_application.guild.name}**\n\n"
        content += "#{message_params[:message_content]}\n\n"
        content += "This message was sent via GuildSync Bot."
        discord_service.send_dm(applicant_discord_connection.discord_user_id, content)
        session.save if session.respond_to?(:save)
        redirect_to guild_invite_members_path(@guild_application.guild), notice: "Message sent to applicant via Discord!"
      rescue => e
        Rails.logger.error "Failed to send message to applicant: #{e.message}"
        session.save if session.respond_to?(:save)
        redirect_to guild_invite_members_path(@guild_application.guild), alert: "Failed to send message: #{e.message}"
      end
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_invite_members_path(@guild_application.guild), alert: "Applicant does not have a Discord connection."
    end
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def set_guild_application
    application = GuildApplication.includes(:guild).find_by(id: params[:id])
    if application && can_manage_applications?(application.guild)
      @guild_application = application
      return
    end

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end

  def guild_application_params
    permitted = params.permit(:guild_id, :discord_username, :message, :character_details)
    sanitize_permitted_text_fields!(permitted, [ :discord_username, :message, :character_details ])
  end

  def message_params
    permitted = params.permit(:message_content)
    sanitize_permitted_text_fields!(permitted, [ :message_content ])
  end

  def interpolate_guild_name(message, guild_name)
    message.to_s
      .gsub("%{guild_name}", guild_name.to_s)
      .gsub("[Guild Name]", guild_name.to_s)
  end

  # Initial GET only — avoids re-filling after validation errors if the applicant cleared the field.
  def apply_initial_discord_username_prefill!
    prefill = current_user.discord_display_name_for_guild_application
    return if prefill.blank?

    @application.discord_username = prefill
  end

  # Same discoverable set as member dashboard (public + not archived).
  def available_guilds_by_game(_user, game = nil)
    scope = Guild.discoverable_for_applications.order(:name)
    return scope if game.blank?

    scope # TODO: filter by game when that feature is implemented
  end
end
