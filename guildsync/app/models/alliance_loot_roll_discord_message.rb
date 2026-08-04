# frozen_string_literal: true

class AllianceLootRollDiscordMessage < ApplicationRecord
  belongs_to :alliance_loot_roll
  belongs_to :guild

  validates :alliance_loot_roll_id, presence: true
  validates :guild_id, presence: true
  validates :channel_id, presence: true
  validates :discord_message_id, presence: true
  validates :guild_id, uniqueness: { scope: :alliance_loot_roll_id }
end
