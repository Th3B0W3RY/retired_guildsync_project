# frozen_string_literal: true

class AllianceEventDiscordMessage < ApplicationRecord
  belongs_to :alliance_event
  belongs_to :guild

  validates :alliance_event_id, presence: true
  validates :guild_id, presence: true
  validates :channel_id, presence: true
  validates :discord_message_id, presence: true
  validates :posted_at, presence: true
  validates :guild_id, uniqueness: { scope: :alliance_event_id }
end
