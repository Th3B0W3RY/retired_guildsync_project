# frozen_string_literal: true

class AlliancePollDiscordMessage < ApplicationRecord
  belongs_to :alliance_poll
  belongs_to :guild

  validates :alliance_poll_id, presence: true
  validates :guild_id, presence: true
  validates :channel_id, presence: true
  validates :discord_message_id, presence: true
  validates :guild_id, uniqueness: { scope: :alliance_poll_id }
end
