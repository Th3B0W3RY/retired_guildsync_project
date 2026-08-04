# frozen_string_literal: true

module Admin
  # Shared scopes for admin subscription lists and dashboard counts (paying vs trials/free).
  class SubscriptionDirectory
    class << self
      def paying_users_relation
        User.joins(current_subscription: :pricing_plan)
            .includes(current_subscription: :pricing_plan)
            .where(subscriptions: { status: :active })
            .where("subscriptions.trial_ends_at IS NULL OR subscriptions.trial_ends_at <= ?", Time.current)
            .where.not(pricing_plans: { name: "Free" })
            .distinct
      end

      def trials_and_free_users_relation
        current_time = Time.current
        active_trial_users = User.joins(current_subscription: :pricing_plan)
                                 .where(subscriptions: { status: :trialing })
                                 .where("subscriptions.trial_ends_at > ?", current_time)
        free_plan_users = User.joins(current_subscription: :pricing_plan)
                              .where(pricing_plans: { name: "Free" })
                              .where(subscriptions: { status: :active })
        User.where(id: active_trial_users.select(:id))
            .or(User.where(id: free_plan_users.select(:id)))
            .includes(current_subscription: :pricing_plan)
            .distinct
      end
    end
  end
end
