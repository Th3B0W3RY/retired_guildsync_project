# frozen_string_literal: true

class GuildActivityLog < ApplicationRecord
  RETENTION_MONTHS = 3

  belongs_to :guild
  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action_type, presence: true
  validates :description, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_guild, ->(guild) { where(guild_id: guild.id) }
  scope :older_than, ->(time) { where("created_at < ?", time) }

  # For pruning: logs older than retention period
  scope :expired, -> { older_than(RETENTION_MONTHS.months.ago) }
end
