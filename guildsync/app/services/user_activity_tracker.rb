# frozen_string_literal: true

# Records the last 10 page visits/actions per user for the dashboard Recent Activity feed.
# Pruning to 10 is done in UserRecentActivity after_create.
class UserActivityTracker
  class << self
    # @param user [User] who performed the action
    # @param path [String] URL path used for de-duplication (e.g. request.path)
    # @param label [String] human-readable description (e.g. "Viewed GuildSync")
    # @param link_path [String, nil] safe href shown in the feed; nil renders as plain text
    # @param record [ApplicationRecord, nil] optional polymorphic subject for the link context
    def record(user:, path:, label:, link_path: nil, record: nil)
      return unless user.present? && path.present? && label.present?
      return if path.length > 2048 || label.length > 500
      return if duplicate_recent?(user, path)

      UserRecentActivity.create!(
        user_id: user.id,
        path: path,
        label: label,
        link_path: link_path,
        subject: record
      )
    rescue => e
      Rails.logger.warn("UserActivityTracker failed: #{e.message}")
    end

    def duplicate_recent?(user, path)
      last = user.user_recent_activities.recent_first.limit(1).first
      last && last.path == path && last.created_at > 30.seconds.ago
    end
  end
end
