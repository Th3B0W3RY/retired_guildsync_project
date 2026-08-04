# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::GuildOwnershipTransferService do
  let(:old_owner) { create(:user, skip_free_plan_subscription: true) }
  let(:new_owner) { create(:user, skip_free_plan_subscription: true) }
  let(:guild) { create(:guild, owner: old_owner) }
  let(:plan) { create(:pricing_plan, name: "Paid Plan", max_guilds: 5, price: 10, price_display: "$10", period: "month") }

  describe ".call" do
    it "transfers ownership and skips billing when not requested" do
      create(:subscription, user: old_owner, pricing_plan: plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)

      result = described_class.call(guild: guild, new_owner: new_owner, cancel_previous_owner_billing: false)

      expect(guild.reload.owner).to eq(new_owner)
      expect(result.billing_outcome).to eq(:not_requested)
      expect(old_owner.reload.current_subscription&.status).to eq("active")
    end

    it "calls SubscriptionCancellationService when the previous owner has no other active guilds" do
      sub = create(:subscription, user: old_owner, pricing_plan: plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)

      result = described_class.call(guild: guild, new_owner: new_owner, cancel_previous_owner_billing: true)

      expect(guild.reload.owner).to eq(new_owner)
      expect(result.billing_outcome).to eq(:applied)
      expect(result.billing_mode).to eq(:local)
      expect(sub.reload.status).to eq("canceled")
      expect(old_owner.reload.current_subscription).to be_nil
    end

    it "does not cancel billing when the previous owner still owns another active guild" do
      create(:subscription, user: old_owner, pricing_plan: plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
      create(:guild, owner: old_owner, name: "Second")

      result = described_class.call(guild: guild, new_owner: new_owner, cancel_previous_owner_billing: true)

      expect(result.billing_outcome).to eq(:skipped_still_owns_guilds)
      expect(old_owner.reload.current_subscription&.status).to eq("active")
    end

    it "reports no_subscription when the previous owner has nothing to cancel" do
      guild # guild factory ensures a subscription for the owner; remove it before billing runs
      old_owner.subscriptions.destroy_all
      old_owner.reload

      result = described_class.call(guild: guild, new_owner: new_owner, cancel_previous_owner_billing: true)

      expect(result.billing_outcome).to eq(:no_subscription)
    end

    it "applies Stripe period_end when the previous owner has a paid Stripe subscription" do
      guild
      old_owner.subscriptions.destroy_all
      create(
        :subscription,
        user: old_owner,
        pricing_plan: plan,
        status: :active,
        started_at: 2.months.ago,
        stripe_subscription_id: "sub_handover_period_end",
        first_paid_invoice_at: 10.days.ago
      )
      stripe_mock = double("Stripe::Subscription", id: "sub_handover_period_end")
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_handover_period_end").and_return(stripe_mock)
      allow(Stripe::Subscription).to receive(:update).with("sub_handover_period_end", { cancel_at_period_end: true })

      result = described_class.call(guild: guild, new_owner: new_owner, cancel_previous_owner_billing: true)

      expect(result.billing_outcome).to eq(:applied)
      expect(result.billing_mode).to eq(:period_end)
      expect(Stripe::Subscription).to have_received(:update).with("sub_handover_period_end", { cancel_at_period_end: true })
    end
  end
end
