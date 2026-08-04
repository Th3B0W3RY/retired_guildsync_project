# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SubscriptionDirectory do
  let(:free_plan) { create(:pricing_plan, name: "Free") }
  let(:paid_plan) { create(:pricing_plan, name: "ProDir") }

  describe ".paying_users_relation" do
    it "includes active non-free subscribers not in an active trial window" do
      paying = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: paying, pricing_plan: paid_plan, status: :active, trial_ends_at: nil)

      on_paid_after_trial = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: on_paid_after_trial, pricing_plan: paid_plan, status: :active, trial_ends_at: 1.day.ago)

      free = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: free, pricing_plan: free_plan, status: :active, trial_ends_at: nil)

      in_trial = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: in_trial, pricing_plan: paid_plan, status: :trialing, trial_ends_at: 1.week.from_now)

      rel = described_class.paying_users_relation
      expect(rel).to include(paying, on_paid_after_trial)
      expect(rel).not_to include(free, in_trial)
    end
  end

  describe ".trials_and_free_users_relation" do
    it "includes active trialing subscriptions and active Free plan users" do
      trialing = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: trialing, pricing_plan: paid_plan, status: :trialing, trial_ends_at: 1.week.from_now)

      free = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: free, pricing_plan: free_plan, status: :active, trial_ends_at: nil)

      paying = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: paying, pricing_plan: paid_plan, status: :active, trial_ends_at: nil)

      rel = described_class.trials_and_free_users_relation
      expect(rel).to include(trialing, free)
      expect(rel).not_to include(paying)
    end
  end
end
