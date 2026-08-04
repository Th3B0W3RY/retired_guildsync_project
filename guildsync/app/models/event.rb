class Event < ApplicationRecord
  include Searchable
  include SoftDeletable

  belongs_to :guild
  belongs_to :created_by, class_name: "User"
  has_many :event_participations, dependent: :destroy
  has_many :participants, through: :event_participations, source: :user
  has_many :discord_event_participations, dependent: :destroy

  soft_delete_metadata display: :title, search: [ :title, :description, :location, :squad_leader ]

  enum :status, {
    scheduled: 0,
    in_progress: 1,
    completed: 2,
    cancelled: 3
  }

  validates :title, presence: true, length: { minimum: 3, maximum: 200 }
  validates :scheduled_at, presence: true
  validates :duration, numericality: { greater_than: 0 }, allow_nil: true

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :past, -> { where("scheduled_at < ?", Time.current).order(scheduled_at: :desc) }

  # When event starts, mark all existing participants as "on_time"
  after_update :mark_participants_on_time, if: :saved_change_to_status?

  set_callback :soft_delete, :before, :purge_discord_artifacts
  before_destroy :purge_discord_artifacts

  private

  def purge_discord_artifacts
    discord_guild_id = guild.discord_id || guild.guild_discord_setting&.discord_guild_id
    bot_token = guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
    return if bot_token.blank?

    service = DiscordService.new(bot_token: bot_token)

    if discord_guild_id.present? && discord_event_id.present?
      begin
        service.delete_scheduled_event!(guild: guild, scheduled_event_id: discord_event_id)
      rescue StandardError => e
        Rails.logger.warn "Event destroy: failed to delete Discord scheduled event: #{e.message}"
      end
    end

    channel_id = guild.guild_discord_setting&.events_channel_id
    if channel_id.present? && discord_message_id.present?
      begin
        service.delete_message(channel_id, discord_message_id)
      rescue StandardError => e
        Rails.logger.warn "Event destroy: failed to delete Discord channel message: #{e.message}"
      end
    end
  end

  def mark_participants_on_time
    # Only mark as on_time when transitioning to in_progress
    previous_status, current_status = saved_change_to_status
    if current_status == "in_progress" && previous_status == "scheduled"
      # Mark all existing discord_event_participations as on_time
      discord_event_participations.update_all(on_time: true)
    end
  end
end
