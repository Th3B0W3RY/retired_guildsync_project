# frozen_string_literal: true

# Tracks Discord slash command executions to guarantee at-most-once
# processing. The unique index on [interaction_token, command_key]
# prevents duplicate side effects when ActiveJob retries a failed job.
class DiscordCommandExecution < ApplicationRecord
  validates :interaction_token, presence: true
  validates :command_key, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending completed failed] }

  scope :completed, -> { where(status: "completed") }

  def self.already_processed?(token, key)
    where(interaction_token: token, command_key: key, status: "completed").exists?
  end

  def self.claim!(token, key)
    create!(interaction_token: token, command_key: key, status: "pending")
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def mark_completed!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_failed!
    update!(status: "failed")
  end
end
