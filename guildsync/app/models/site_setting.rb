# frozen_string_literal: true

class SiteSetting < ApplicationRecord
  DEFAULTS = {
    "release_notes_url" => "https://guildsync.raiseaticket.com",
    "homepage_footer_documentation_url" => "https://guildsync.raiseaticket.com",
    "homepage_footer_contact_url" => "https://guildsync.raiseaticket.com",
    "homepage_footer_discord_url" => ENV["COMMUNITY_DISCORD_INVITE_URL"].presence || "https://discord.com/widget?id=1499890686021992539&theme=dark",
    "error_notify_discord_usernames" => '["thecinopewpew","breezybeast4"]',
    "flash_toast_duration_ms" => "2500",
    "error_batch_cadence_hours" => "24",
    "error_immediate_severities" => '["urgent"]',
    "landing_feedback_carousel_interval_ms" => "6000"
  }.freeze

  LANDING_FEEDBACK_CAROUSEL_INTERVAL_MIN_MS = 2_000
  LANDING_FEEDBACK_CAROUSEL_INTERVAL_MAX_MS = 60_000
  LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS = 6_000

  FLASH_TOAST_DURATION_MIN_MS = 500
  FLASH_TOAST_DURATION_MAX_MS = 60_000
  FLASH_TOAST_DURATION_DEFAULT_MS = 2500

  ERROR_BATCH_CADENCE_MIN = 1
  ERROR_BATCH_CADENCE_MAX = 8760
  ERROR_BATCH_CADENCE_DEFAULT = 24

  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  def self.get(key)
    find_by(key: key)&.value || DEFAULTS[key.to_s]
  rescue ActiveRecord::ActiveRecordError
    DEFAULTS[key.to_s]
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
    record
  end

  def self.release_notes_url
    get("release_notes_url")
  end

  def self.homepage_footer_documentation_url
    get("homepage_footer_documentation_url")
  end

  def self.homepage_footer_contact_url
    get("homepage_footer_contact_url")
  end

  def self.homepage_footer_discord_url
    get("homepage_footer_discord_url")
  end

  def self.error_notify_discord_usernames
    fallback = %w[thecinopewpew breezybeast4]
    raw = get("error_notify_discord_usernames")
    return fallback if raw.blank?

    parsed = JSON.parse(raw)
    return fallback unless parsed.is_a?(Array)

    parsed.filter_map { |u| u.to_s.strip.presence }
  rescue JSON::ParserError
    fallback
  end

  def self.landing_feedback_carousel_interval_ms
    raw = get("landing_feedback_carousel_interval_ms")
    n = Integer(raw, exception: false)
    if n.nil? || n < LANDING_FEEDBACK_CAROUSEL_INTERVAL_MIN_MS || n > LANDING_FEEDBACK_CAROUSEL_INTERVAL_MAX_MS
      return LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS
    end

    n
  end

  def self.flash_toast_duration_ms
    raw = get("flash_toast_duration_ms")
    n = Integer(raw, exception: false)
    return FLASH_TOAST_DURATION_DEFAULT_MS if n.nil? || n < FLASH_TOAST_DURATION_MIN_MS || n > FLASH_TOAST_DURATION_MAX_MS

    n
  end

  def self.error_batch_cadence_hours
    raw = get("error_batch_cadence_hours")
    n = Integer(raw, exception: false)
    return ERROR_BATCH_CADENCE_DEFAULT if n.nil? || n < ERROR_BATCH_CADENCE_MIN || n > ERROR_BATCH_CADENCE_MAX

    n
  end

  def self.error_immediate_severities
    default = ["urgent"]
    raw = get("error_immediate_severities")
    return default if raw.blank?

    parsed = JSON.parse(raw)
    return default unless parsed.is_a?(Array)

    parsed.map(&:to_s).select { |s| ErrorLog::SEVERITIES.include?(s) }
  rescue JSON::ParserError
    default
  end
end
