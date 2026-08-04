# frozen_string_literal: true

class AccountDeletionJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: "default"

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?
    return if user.account_data_purged_at.present?
    return if user.account_closure_soft_completed_at.present?

    AccountDeletion::PurgeService.new(user).call_soft

    user.reload
    return if user.account_closed_at.blank?

    run_at = user.account_closed_at + SoftDeletable::RETENTION_PERIOD
    AccountHardPurgeJob.perform_at(run_at, user_id)
  end
end
