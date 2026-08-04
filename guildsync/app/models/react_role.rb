# frozen_string_literal: true

class ReactRole < ApplicationRecord
  belongs_to :guild

  validates :position, presence: true,
                       inclusion: { in: 1..3, message: "must be 1, 2, or 3" },
                       uniqueness: { scope: :guild_id }
  validates :role_id, presence: true
  validates :role_name, presence: true
  validates :emoji_name, presence: true
  validate :role_must_be_synced

  scope :ordered, -> { order(:position) }

  # Returns the emoji string suitable for displaying in Discord embeds.
  # Unicode: raw character; Custom: <:name:id> or <a:name:id> for animated.
  def display_emoji
    if is_custom_emoji?
      "<:#{emoji_name}:#{emoji_id}>"
    else
      emoji_name
    end
  end

  # Returns the emoji string required by the Discord Create Reaction API.
  # Unicode: raw character; Custom: "name:id".
  def api_emoji
    is_custom_emoji? ? "#{emoji_name}:#{emoji_id}" : emoji_name
  end

  private

  def role_must_be_synced
    return if guild&.discord_role_syncs&.exists?(role_id: role_id)

    errors.add(:role_id, "must be a synced Discord role for this guild")
  end
end
