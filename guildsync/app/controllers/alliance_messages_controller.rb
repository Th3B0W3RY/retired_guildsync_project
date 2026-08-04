# frozen_string_literal: true

class AllianceMessagesController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member

  def index
    preserve_session
    @message_type   = params[:type] == "gm" ? :gm_only : :all_members
    @can_see_gm_chat = gm_in_alliance?

    if @message_type == :gm_only && !@can_see_gm_chat
      respond_to do |format|
        format.html do
          redirect_to alliance_alliance_messages_path(@alliance), alert: t("alliances.messages.errors.gm_only")
        end
        format.json { render json: { error: t("alliances.messages.errors.gm_only") }, status: :forbidden }
      end
      return
    end

    @messages = @alliance.alliance_messages
                         .where(message_type: @message_type)
                         .includes(:sender)
                         .chronological
                         .last(100)
    @new_message = AllianceMessage.new

    respond_to do |format|
      format.html
      format.json do
        since_id = params[:since_id].to_i
        since_id = 0 if since_id.negative?
        scope = @alliance.alliance_messages.where(message_type: @message_type)
        new_msgs =
          if since_id.positive?
            scope.where("alliance_messages.id > ?", since_id).includes(:sender).chronological
          else
            scope.none
          end
        time_fmt = I18n.t("alliances.messages.index.message_time_format")
        render json: { messages: new_msgs.map { |m| message_json(m, time_fmt) } }
      end
    end
  end

  def create
    preserve_session
    message_type = params[:message_type] == "gm_only" ? :gm_only : :all_members

    if message_type == :gm_only && !gm_in_alliance?
      render json: { error: t("alliances.messages.errors.gm_only") }, status: :forbidden
      return
    end

    content = params.dig(:alliance_message, :content).to_s.strip
    if content.blank?
      render json: { error: t("alliances.messages.errors.blank") }, status: :unprocessable_entity
      return
    end

    msg = @alliance.alliance_messages.create!(
      sender:       current_user,
      content:      content,
      message_type: message_type
    )

    AllianceMessagesChannel.broadcast_new_message(
      @alliance.id,
      message_type.to_s,
      cable_message_payload(msg)
    )

    time_fmt = I18n.t("alliances.messages.index.message_time_format")
    render json: message_json(msg, time_fmt)
  end

  private

  def message_json(msg, time_fmt)
    {
      id:           msg.id,
      content:      msg.content,
      sender:       msg.sender.display_name,
      sender_id:    msg.sender_id,
      created_at:   msg.created_at.utc.iso8601,
      display_time: I18n.l(msg.created_at, format: time_fmt)
    }
  end

  # Locale-neutral payload for Action Cable; clients format time via Intl + datetime.
  def cable_message_payload(msg)
    {
      id:         msg.id,
      content:    msg.content,
      sender:     msg.sender.display_name,
      sender_id:  msg.sender_id,
      created_at: msg.created_at.utc.iso8601
    }
  end

  def gm_in_alliance?
    current_user.owned_guilds.any? do |guild|
      @alliance.active_guild_ids.include?(guild.id)
    end
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
