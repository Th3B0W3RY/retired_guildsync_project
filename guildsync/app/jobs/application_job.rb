# frozen_string_literal: true

# Base class for all background jobs
# All jobs should inherit from this class
#
# Example:
#   class SendWelcomeEmailJob < ApplicationJob
#     queue_as :mailers
#
#     def perform(user_id)
#       user = User.find(user_id)
#       UserMailer.welcome_email(user).deliver_now
#     end
#   end
#
# Enqueue a job (use perform_later; ApplicationJob is ActiveJob, not Sidekiq::Worker):
#   SendWelcomeEmailJob.perform_later(user.id)
#   SendWelcomeEmailJob.set(wait: 1.hour).perform_later(user.id)

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encounter a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
