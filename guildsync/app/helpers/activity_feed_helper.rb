# frozen_string_literal: true

module ActivityFeedHelper
  def format_activity_action_type(action_type)
    return action_type if action_type.blank?

    key = "activity_feed.action_types.#{action_type}"
    t(key, default: action_type.to_s.humanize)
  end
end
