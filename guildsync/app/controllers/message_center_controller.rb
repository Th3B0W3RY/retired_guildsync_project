# frozen_string_literal: true

class MessageCenterController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :ensure_guild_member
  before_action :require_message_center_plan!

  def index
    preserve_session
  end

  def search_recipients
    q = sanitize_search_input(params[:q])
    results = []

    # Guild members (excluding self)
    members = @guild.members.where.not(id: current_user.id)
    members = members.where("username ILIKE :q OR email ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(q)}%") if q.present?
    members = members.limit(20)
    members.each do |u|
      results << { id: u.id, name: u.display_name, username: u.username, email: u.email, type: "member" }
    end

    # If current user is guild owner: also search other guild owners (excluding self and already-listed members)
    if @guild.owner_id == current_user.id && q.present?
      owner_ids = Guild.distinct.pluck(:owner_id).reject { |id| id == current_user.id }
      already_ids = results.map { |r| r[:id] }
      other_owners = User.where(id: owner_ids).where.not(id: already_ids)
      other_owners = other_owners.where("username ILIKE :q OR email ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(q)}%")
      other_owners.limit(10).each do |u|
        results << { id: u.id, name: u.display_name, username: u.username, email: u.email, type: "owner" }
      end
    end

    render json: results.uniq { |r| r[:id] }
  end

  def conversation
    recipient = User.find_by(id: params[:recipient_id])
    unless recipient && can_message?(recipient)
      render json: { error: t("message_center.invalid_recipient") }, status: :unprocessable_entity
      return
    end

    messages = DirectMessage.between(current_user, recipient)
      .where("guild_id IS NULL OR guild_id = ?", @guild.id)
      .recent_first
      .limit(100)
      .to_a
      .reverse

    render json: messages.map { |m|
      {
        id: m.id,
        sender_id: m.sender_id,
        content: m.content,
        created_at: m.created_at.iso8601
      }
    }
  end

  def create
    recipient = User.find_by(id: params[:recipient_id])
    unless recipient && can_message?(recipient)
      render json: { error: t("message_center.invalid_recipient") }, status: :unprocessable_entity
      return
    end

    content = sanitize_text_input(params[:content]).to_s
    if content.blank?
      render json: { error: t("message_center.content_blank") }, status: :unprocessable_entity
      return
    end

    msg = DirectMessage.new(
      sender: current_user,
      recipient: recipient,
      guild_id: guild_id_for_conversation(recipient),
      content: content
    )
    if msg.save
      deliver_message_center_dm(msg, recipient)
      render json: { id: msg.id, created_at: msg.created_at.iso8601 }
    else
      render json: { error: msg.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def deliver_message_center_dm(msg, recipient)
    conn = recipient.user_discord_connection
    return unless conn&.discord_user_id.present?

    sender_name = current_user.display_name.presence || current_user.username.presence || "Someone"
    guild_label = @guild.name.presence || "GuildSync"
    content = "**Message from #{sender_name}** (#{guild_label}):\n\n#{msg.content}"
    discord_service = DiscordService.new
    discord_service.send_dm(conn.discord_user_id, content)
  rescue RestClient::RequestTimeout, RestClient::ServerBrokeConnection => e
    if defined?(GuildsyncLoggers)
      GuildsyncLoggers.error(
        GuildsyncLoggers.discord_failures,
        "Message Center DM timeout | recipient_id=#{recipient.id} sender_id=#{msg.sender_id} direct_message_id=#{msg.id} | #{e.class}: #{e.message}"
      )
      GuildsyncLoggers.log_exception(GuildsyncLoggers.discord_failures, e, recipient_id: recipient.id, sender_id: msg.sender_id, direct_message_id: msg.id, context: "message_center_dm_timeout")
    end
    Rails.logger.warn "Message Center Discord DM timeout: #{e.message}"
  rescue RestClient::ExceptionWithResponse => e
    if defined?(GuildsyncLoggers)
      GuildsyncLoggers.error(
        GuildsyncLoggers.discord_failures,
        "Message Center DM failed | recipient_id=#{recipient.id} sender_id=#{msg.sender_id} direct_message_id=#{msg.id} | #{e.response&.code} #{e.response&.body&.slice(0, 500)}"
      )
      GuildsyncLoggers.log_exception(GuildsyncLoggers.discord_failures, e, recipient_id: recipient.id, sender_id: msg.sender_id, direct_message_id: msg.id, response_code: e.response&.code, response_body: e.response&.body&.slice(0, 500), context: "message_center_dm_api")
    end
    Rails.logger.warn "Message Center Discord DM failed: #{e.response&.code} #{e.response&.body}"
  rescue => e
    if defined?(GuildsyncLoggers)
      GuildsyncLoggers.log_exception(GuildsyncLoggers.discord_failures, e, recipient_id: recipient.id, sender_id: msg.sender_id, direct_message_id: msg.id, context: "message_center_dm")
    end
    Rails.logger.warn "Message Center Discord DM error: #{e.class} #{e.message}"
  end

  def set_guild
    gid = params[:id]
    @guild = current_user.guilds.find_by(id: gid)
    @guild ||= current_user.owned_guilds.find_by(id: gid)
    @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)
    return if @guild

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end

  def require_message_center_plan!
    return if current_user.plan_allows?(:message_center)

    redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
  end

  def ensure_guild_member
    return if @guild.members.include?(current_user) && can_use_message_center?(@guild)

    redirect_to guild_path(@guild), alert: t("message_center.access_denied")
  end

  def can_message?(recipient)
    return false if recipient.id == current_user.id

    # Can message guild members of this guild
    return true if @guild.members.include?(recipient)

    # Guild owners can message other guild owners (any)
    return true if @guild.owner_id == current_user.id && recipient.owned_guilds.any?

    false
  end

  def guild_id_for_conversation(recipient)
    # In-guild conversation: store guild_id. Owner-to-owner (recipient not in guild): store nil.
    return @guild.id if @guild.members.include?(recipient)

    nil
  end

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
