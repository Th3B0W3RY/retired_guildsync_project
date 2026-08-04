# frozen_string_literal: true

module Billing
  # Stripe Checkout subscription trials: Basic plan only (14 days, see User::STANDARD_TRIAL_PERIOD_DAYS).
  class TrialPolicy
    class << self
      def stripe_trial_period_days(pricing_plan)
        return nil if pricing_plan.blank?
        return User::STANDARD_TRIAL_PERIOD_DAYS if pricing_plan.name.to_s.strip.casecmp?("basic")
        nil
      end
    end
  end
end
