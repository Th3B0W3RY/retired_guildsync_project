# frozen_string_literal: true

module AccountDeletion
  module RateLimits
    SEND_PER_HOUR = Integer(ENV.fetch("ACCOUNT_DELETION_SEND_LIMIT_PER_HOUR", "5"))
    CONFIRM_PER_HOUR = Integer(ENV.fetch("ACCOUNT_DELETION_CONFIRM_LIMIT_PER_HOUR", "20"))
  end

  def self.feature_enabled?
    return true unless Rails.env.production?

    ENV["ACCOUNT_SELF_DELETE_ENABLED"].to_s != "0"
  end
end
