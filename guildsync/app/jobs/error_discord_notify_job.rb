# frozen_string_literal: true

# Best-effort Discord notification for ErrorLog rows. Must never raise out of #perform.
#
# Delivery paths (optional; any combination):
# 1. +ERROR_NOTIFY_DISCORD_WEBHOOK_URL+ — incoming webhook POST (content truncated for Discord limits).
# 2. +DISCORD_BOT_TOKEN+ + SiteSetting.error_notify_discord_usernames — DMs GuildSync users by +users.username+
#    (case-insensitive) who have +user_discord_connection.discord_user_id+.
class ErrorDiscordNotifyJob < ApplicationJob
  queue_as :default

  MAX_DM_LENGTH = 1800
  MAX_WEBHOOK_CONTENT = 1900

  def perform(error_log_id)
    log = ErrorLog.find_by(id: error_log_id)
    return unless log

    body = build_message(log)
    post_webhook_if_configured(body)
    dm_configured_users(body)
  rescue StandardError => e
    Rails.logger.error "[ErrorDiscordNotifyJob] #{e.class}: #{e.message}"
  end

  private

  def build_message(log)
    link = admin_error_link(log)
    core = <<~TXT.squish
      [GuildSync Error #{log.severity.to_s.upcase}] #{log.error_class}: #{log.message.to_s.truncate(1600)}
    TXT
    link.present? ? "#{core} — #{link}" : core
  end

  def admin_error_link(log)
    base = ENV["APP_URL"].to_s.presence&.chomp("/")
    return "#{base}/admin/errors/#{log.id}" if base.present?

    Rails.application.routes.url_helpers.admin_error_url(log)
  rescue StandardError => e
    Rails.logger.warn "[ErrorDiscordNotifyJob] admin URL fallback: #{e.message}"
    "/admin/errors/#{log.id}"
  end

  def post_webhook_if_configured(body)
    url = ENV["ERROR_NOTIFY_DISCORD_WEBHOOK_URL"].to_s.strip.presence
    return if url.blank?

    payload = { content: body.to_s.truncate(MAX_WEBHOOK_CONTENT) }.to_json
    RestClient.post(url, payload, { "Content-Type" => "application/json" })
    Rails.logger.info "[ErrorDiscordNotifyJob] posted to ERROR_NOTIFY_DISCORD_WEBHOOK_URL"
  rescue StandardError => e
    Rails.logger.error "[ErrorDiscordNotifyJob] webhook failed: #{e.class}: #{e.message}"
  end

  def dm_configured_users(body)
    token = ENV["DISCORD_BOT_TOKEN"].to_s.presence
    if token.blank?
      Rails.logger.info "[ErrorDiscordNotifyJob] DISCORD_BOT_TOKEN not set; skipping DMs"
      return
    end

    usernames = SiteSetting.error_notify_discord_usernames
    if usernames.blank?
      Rails.logger.info "[ErrorDiscordNotifyJob] no usernames in error_notify_discord_usernames; skipping DMs"
      return
    end

    service = DiscordService.new(bot_token: token)
    text = body.to_s.truncate(MAX_DM_LENGTH)

    usernames.each do |raw|
      send_dm_for_username(service, normalize_notify_username(raw), text)
    end
  end

  def normalize_notify_username(raw)
    raw.to_s.strip.split("#").first.to_s.strip
  end

  def send_dm_for_username(service, username, text)
    if username.blank?
      Rails.logger.warn "[ErrorDiscordNotifyJob] skip empty username in notify list"
      return
    end

    user = User.where("LOWER(username) = ?", username.downcase).first
    unless user
      Rails.logger.warn "[ErrorDiscordNotifyJob] no GuildSync user with username #{username.inspect}"
      return
    end

    discord_id = user.user_discord_connection&.discord_user_id
    unless discord_id.present?
      Rails.logger.warn "[ErrorDiscordNotifyJob] user #{username.inspect} has no linked Discord account; skip DM"
      return
    end

    service.send_dm(discord_id, text)
    Rails.logger.info "[ErrorDiscordNotifyJob] sent DM to @#{username}"
  rescue StandardError => e
    Rails.logger.error "[ErrorDiscordNotifyJob] DM to #{username.inspect} failed: #{e.class}: #{e.message}"
  end
end
