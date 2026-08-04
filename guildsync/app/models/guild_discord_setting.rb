class GuildDiscordSetting < ApplicationRecord
  belongs_to :guild

  encrypts :bot_token, support_unencrypted_data: true

  validates :discord_guild_id, presence: true, uniqueness: { message: :already_connected }
  validates :guild_id, uniqueness: { message: :one_connection_only }
  validates :default_timezone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name), allow_blank: true }

  after_save :update_guild_discord_id

  def connected?
    discord_guild_id.present? && connected_at.present?
  end

  def events_channel_configured?
    events_channel_id.present?
  end

  def gear_channel_configured?
    gear_channel_id.present?
  end

  def polls_channel_configured?
    polls_channel_id.present?
  end

  def loot_rolls_channel_configured?
    loot_rolls_channel_id.present?
  end

  def alliance_events_channel_configured?
    alliance_events_channel_id.present?
  end

  def alliance_polls_channel_configured?
    alliance_polls_channel_id.present?
  end

  def alliance_loot_rolls_channel_configured?
    alliance_loot_rolls_channel_id.present?
  end

  def alliance_invites_channel_configured?
    alliance_invites_channel_id.present?
  end

  # Fallback: invites channel, else first configured alliance content channel (documented in settings copy).
  def alliance_channel_for_invite_notification
    alliance_invites_channel_id.presence ||
      alliance_events_channel_id.presence ||
      alliance_polls_channel_id.presence ||
      alliance_loot_rolls_channel_id.presence
  end

  def timezone
    default_timezone.presence || "Eastern Time (US & Canada)"
  end

  private

  def update_guild_discord_id
    if discord_guild_id.present? && guild.discord_id != discord_guild_id
      guild.update_column(:discord_id, discord_guild_id)
    end
  end
end
