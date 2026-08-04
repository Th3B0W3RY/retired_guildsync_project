# frozen_string_literal: true

class GuildInvitesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_invite, only: [ :show, :accept, :deny, :dismiss ]

  def show
    preserve_session
    @guild = @invite.guild
  end

  def accept
    preserve_session
    unless @invite.pending?
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: "This invite is no longer valid."
      return
    end

    unless @invite.user_id == current_user.id
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: "This invite is not for you."
      return
    end

    # Check if user is already a member
    if @invite.guild.guild_members.exists?(user_id: current_user.id)
      # Use update_column to bypass validations since we're just updating status
      @invite.update_column(:status, :accepted)
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@invite.guild), notice: "Welcome to #{@invite.guild.name}!"
      return
    end

    # Add user to guild with default role
    guild = @invite.guild
    member = guild.guild_members.create(
      user: current_user,
      role: :member,
      status: :active,
      discord_role_id: guild.default_role_id # Always set default role if configured
    )
    unless member.persisted?
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: member.errors.full_messages.to_sentence.presence || t("compliance.ip_conflict.warning_message")
      return
    end

    # Apply default Discord role to Discord server if set and user has Discord connection
    if guild.default_role_id.present? && guild.guild_discord_setting&.connected? && current_user.user_discord_connection&.discord_user_id.present?
      begin
        discord_service = DiscordService.new
        discord_guild_id = guild.guild_discord_setting.discord_guild_id
        discord_user_id = current_user.user_discord_connection.discord_user_id

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

    @invite.update!(status: :accepted)

    session.save if session.respond_to?(:save)
    redirect_to guild_path(guild), notice: "Welcome to #{guild.name}!"
  end

  def deny
    preserve_session
    unless @invite.pending?
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: "This invite is no longer valid."
      return
    end

    unless @invite.user_id == current_user.id
      session.save if session.respond_to?(:save)
      redirect_to dashboard_path, alert: "This invite is not for you."
      return
    end

    @invite.update!(status: :denied)

    # Notify guild owner via Discord if they have Discord connection
    guild = @invite.guild
    owner = guild.owner
    if owner.user_discord_connection&.discord_user_id.present?
      begin
        discord_service = DiscordService.new
        deny_message = "The applicant has denied your invite, sorry!"
        discord_service.send_dm(owner.user_discord_connection.discord_user_id, deny_message)
      rescue => e
        Rails.logger.error "Failed to send deny notification to guild owner: #{e.message}"
        # Continue even if Discord DM fails
      end
    end

    session.save if session.respond_to?(:save)
    redirect_to dashboard_path, notice: "You've declined the invite to #{guild.name}."
  end

  def dismiss
    preserve_session
    unless @invite.guild.owner_id == current_user.id || can_manage_applications?(@invite.guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_review_applications_path(@invite.guild), alert: "You do not have permission to dismiss invites."
      return
    end

    @invite.update_column(:dismissed, true)
    session.save if session.respond_to?(:save)
    redirect_to guild_review_applications_path(@invite.guild), notice: "Invite dismissed."
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def set_invite
    @invite = current_user.guild_invites.find_by(id: params[:id])
    return if @invite

    if action_name == "dismiss"
      invite = GuildInvite.find_by(id: params[:id])
      if invite && (invite.guild.owner_id == current_user.id || can_manage_applications?(invite.guild))
        @invite = invite
        return
      end
    end

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end
end
