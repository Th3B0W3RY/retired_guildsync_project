# frozen_string_literal: true

# Runs the destructive account purge (graph destroy + tombstone) after the retention window.
# See AccountDeletion::PurgeService#call_hard.
class AccountHardPurgeJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: "default"

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?
    return if user.account_data_purged_at.present?
    return if user.account_closed_at.blank?

    AccountDeletion::PurgeService.new(user).call_hard
  end
end
