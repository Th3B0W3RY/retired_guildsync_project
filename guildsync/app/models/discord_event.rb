class DiscordEvent < ApplicationRecord
  include Searchable
  include SoftDeletable

  belongs_to :guild
  belongs_to :discord_connection
  has_many :discord_event_signups, dependent: :destroy

  soft_delete_metadata display: :title, search: [ :title, :description, :event_type ]

  validates :discord_event_id, presence: true
  validates :channel_id, presence: true
  validates :title, presence: true
  validates :scheduled_at, presence: true
  validate :discord_event_id_unique_across_deleted_records

  EVENT_TYPES = %w[
    pvp
    guild_scrim
    gvg
    regular_scrim
    pve_event
    world_boss
    guild_questing_time
  ].freeze

  ROLE_CATEGORIES = %w[dps tank healer ranged].freeze

  ROLE_EMOJIS = {
    "dps" => "🗡️",
    "tank" => "🛡️",
    "healer" => "✚",
    "ranged" => "🏹"
  }.freeze

  def signups_by_role
    discord_event_signups.group_by(&:role)
  end

  def signup_count_for_role(role)
    # Only count users with on_time status
    discord_event_signups.where(role: role, status: :on_time).count
  end

  def on_time_signups_by_role
    # Group only on_time signups by role
    discord_event_signups.where(status: :on_time).group_by(&:role)
  end

  private

  def discord_event_id_unique_across_deleted_records
    return if discord_event_id.blank?
    return unless self.class.unscoped.where(discord_event_id: discord_event_id).where.not(id: id).exists?

    errors.add(:discord_event_id, :taken)
  end
end
