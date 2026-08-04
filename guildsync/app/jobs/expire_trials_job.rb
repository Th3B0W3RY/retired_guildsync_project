class ExpireTrialsJob
  include Sidekiq::Worker

  def perform
    # 1) Send warning emails for trials that are about to expire (within 3 days)
    warning_cutoff = 3.days.from_now
    warning_trials = Subscription.where(status: :trialing)
                                 .where("trial_ends_at BETWEEN ? AND ?", Time.current, warning_cutoff)
                                 .where(trial_warning_sent_at: nil)

    warning_trials.find_each do |subscription|
      begin
        TrialMailer.trial_expiring(subscription.id).deliver_later
        subscription.update!(trial_warning_sent_at: Time.current)
      rescue => e
        Rails.logger.error("ExpireTrialsJob warning failed for subscription #{subscription.id}: #{e.class} - #{e.message}")
      end
    end

    # 2) Find all subscriptions in trial that have expired and either activate paid
    #    or downgrade to Free mode.
    expired_trials = Subscription.where(status: :trialing)
                                  .where("trial_ends_at < ?", Time.current)

    expired_trials.find_each do |subscription|
      user = subscription.user

      # Check if user has a Stripe subscription (payment method added)
      has_stripe_subscription = subscription.stripe_subscription_id.present?

      if has_stripe_subscription
        # User added payment method - activate paid plan
        subscription.update!(
          status: :active,
          expires_at: nil # Paid plans don't expire
        )
        Rails.logger.info("Activated paid subscription for user: #{user.id}, subscription: #{subscription.id}")
      else
        # No payment method - convert to Free plan
        user.convert_expired_trial_to_free!
        Rails.logger.info("Converted expired trial to Free plan for user: #{user.id}, subscription: #{subscription.id}")
      end
    end

    Rails.logger.info("Processed #{expired_trials.count} expired trials")
  end
end
