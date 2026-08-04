# frozen_string_literal: true

class AllianceEvent < ApplicationRecord
  include SoftDeletable

  # [display label, slug] for alliance event form and Discord embeds (alliance-only; guild DiscordEvent uses its own list).
  EVENT_TYPE_OPTIONS = [
    [ "PvP", "pvp" ],
    [ "Custom Event", "custom_event" ],
    [ "Alliance Quest", "alliance_quest" ],
    [ "Quest", "quest" ],
    [ "Scrim", "scrim" ],
    [ "PvE Event", "pve_event" ],
    [ "PvP Event", "pvp_event" ],
    [ "War", "war" ],
    [ "Nodewar", "nodewar" ],
    [ "Siege", "siege" ],
    [ "World Boss", "world_boss" ],
    [ "Dungeon Boss", "dungeon_boss" ],
    [ "Raidboss", "raidboss" ],
    [ "Meeting", "meeting" ],
    [ "War Review", "war_review" ],
    [ "Gear Review", "gear_review" ]
  ].freeze

  EVENT_TYPE_SLUGS = EVENT_TYPE_OPTIONS.map(&:last).freeze

  LEGACY_EVENT_TYPE_SLUGS = %w[
    guild_scrim
    gvg
    regular_scrim
    guild_questing_time
  ].freeze

  EVENT_TYPE_LABELS = EVENT_TYPE_OPTIONS.each_with_object({}) { |(label, slug), h| h[slug] = label }.freeze

  LEGACY_EVENT_TYPE_LABELS = {
    "guild_scrim" => "Guild Scrim",
    "gvg" => "Gvg",
    "regular_scrim" => "Regular Scrim",
    "guild_questing_time" => "Guild Questing Time"
  }.freeze

  def self.event_type_label(slug)
    return "General" if slug.blank?

    EVENT_TYPE_LABELS[slug] || LEGACY_EVENT_TYPE_LABELS[slug] || slug.to_s.tr("_", " ").titleize
  end

  belongs_to :alliance
  belongs_to :created_by, class_name: "User"
  has_many   :alliance_event_participations, dependent: :destroy
  has_many   :alliance_event_discord_signups, dependent: :destroy
  has_many   :alliance_event_discord_messages, dependent: :destroy
  has_many   :participants, through: :alliance_event_participations, source: :user

  soft_delete_metadata display: :title, search: [ :title, :description, :location, :squad_leader ]

  enum :status, { scheduled: 0, in_progress: 1, completed: 2, cancelled: 3 }

  validates :title,        presence: true, length: { minimum: 3, maximum: 200 }
  validates :scheduled_at, presence: true
  validates :duration,     numericality: { greater_than: 0 }, allow_nil: true
  validates :event_type,   inclusion: { in: EVENT_TYPE_SLUGS + LEGACY_EVENT_TYPE_SLUGS }, allow_blank: true

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :past,     -> { where("scheduled_at < ?", Time.current).order(scheduled_at: :desc) }
  scope :ordered,  -> { order(:scheduled_at) }

  # Role signup buttons posted to Discord (subset of AllianceDiscordBroadcastService::ROLE_CATEGORIES)
  def role_categories_for_discord
    cats = role_categories
    cats = AllianceDiscordBroadcastService::ROLE_CATEGORIES if cats.blank?
    if cats.is_a?(String)
      cats = JSON.parse(cats)
    end
    Array(cats).map(&:to_s) & AllianceDiscordBroadcastService::ROLE_CATEGORIES
  rescue JSON::ParserError
    AllianceDiscordBroadcastService::ROLE_CATEGORIES.dup
  end
end
