# frozen_string_literal: true

# Records user-facing guild activity for the Activity Feed.
# Only actions performed by a guild member while in guild context (guild pages/menus) should be logged.
# Store only human-readable descriptions and minimal metadata (no stack traces or internal IDs).
class GuildActivityLogger
  class << self
    # @param guild [Guild]
    # @param user [User, nil] who performed the action
    # @param action_type [String] e.g. "document_created", "member_invited"
    # @param description [String] user-facing one-line description
    # @param subject [ApplicationRecord, nil] optional polymorphic subject
    # @param metadata [Hash] optional extra context (names, titles only - no raw IDs for display)
    def log(guild:, user: nil, action_type:, description:, subject: nil, **metadata)
      return unless guild.present?
      # Only log if the actor is a member of the guild (or nil for system). Never track non-member actions.
      if user.present?
        return unless guild.guild_members.exists?(user_id: user.id, status: :active)
      end

      GuildActivityLog.create!(
        guild_id: guild.id,
        user_id: user&.id,
        action_type: action_type.to_s,
        description: description.to_s.truncate(500),
        subject: subject,
        metadata: metadata.slice(:title, :name, :target_name, :reason, :ocr_billed_to_name).compact
      )
    rescue => e
      Rails.logger.warn("GuildActivityLogger failed: #{e.message}")
    end
  end
end
