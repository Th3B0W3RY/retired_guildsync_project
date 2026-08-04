# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionCancellationService do
  let(:user) { create(:user, skip_free_plan_subscription: true) }
  let(:plan) do
    create(:pricing_plan, name: "Paid Cancel Spec", max_guilds: 5, price: 10, price_display: "$10", period: "month")
  end

  describe ".call" do
    it "returns failure when there is no current subscription" do
      result = described_class.call(user: user)

      expect(result.ok).to be false
      expect(result.error).to eq("No subscription to cancel.")
      expect(result.mode).to be_nil
    end

    context "when stripe_subscription_id is blank" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
      end

      it "cancels the local subscription record" do
        result = described_class.call(user: user)

        expect(result.ok).to be true
        expect(result.mode).to eq(:local)
        expect(subscription.reload.status).to eq("canceled")
      end
    end

    context "when Stripe subscription exists but no paid invoice timestamp" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: plan,
          status: :active,
          started_at: 1.week.ago,
          stripe_subscription_id: "sub_immediate_spec",
          first_paid_invoice_at: nil
        )
      end

      before do
        stripe_sub = double("Stripe::Subscription", id: "sub_immediate_spec")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_immediate_spec").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:cancel).with("sub_immediate_spec")
      end

      it "cancels in Stripe immediately" do
        result = described_class.call(user: user)

        expect(result.ok).to be true
        expect(result.mode).to eq(:immediate_no_payment)
        expect(Stripe::Subscription).to have_received(:cancel).with("sub_immediate_spec")
      end
    end

    context "when paid and outside refund window" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: plan,
          status: :active,
          started_at: 2.months.ago,
          stripe_subscription_id: "sub_period_end_spec",
          first_paid_invoice_at: 10.days.ago
        )
      end

      before do
        stripe_sub = double("Stripe::Subscription", id: "sub_period_end_spec")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_period_end_spec").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:update).with("sub_period_end_spec", { cancel_at_period_end: true })
      end

      it "schedules cancellation at period end" do
        result = described_class.call(user: user)

        expect(result.ok).to be true
        expect(result.mode).to eq(:period_end)
        expect(Stripe::Subscription).to have_received(:update).with("sub_period_end_spec", { cancel_at_period_end: true })
      end
    end

    context "when refund window applies" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: plan,
          status: :active,
          started_at: 2.days.ago,
          stripe_subscription_id: "sub_refund_spec",
          first_paid_invoice_at: 1.day.ago
        )
      end

      before do
        stripe_sub = double("Stripe::Subscription", id: "sub_refund_spec")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_refund_spec").and_return(stripe_sub)
        invoices = double("InvoiceList")
        allow(invoices).to receive(:auto_paging_each) { |_block| nil }
        allow(Stripe::Invoice).to receive(:list).with(subscription: "sub_refund_spec", status: "paid", limit: 100).and_return(invoices)
        allow(Stripe::Subscription).to receive(:cancel).with("sub_refund_spec")
      end

      it "refund path runs and subscription is canceled in Stripe" do
        result = described_class.call(user: user)

        expect(result.ok).to be true
        expect(result.mode).to eq(:refund_and_cancel)
        expect(Stripe::Subscription).to have_received(:cancel).with("sub_refund_spec")
      end
    end

    context "when Stripe raises" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: plan,
          status: :active,
          started_at: Time.current,
          stripe_subscription_id: "sub_error_spec",
          first_paid_invoice_at: nil
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_raise(Stripe::StripeError.new("card declined"))
      end

      it "returns a failure result" do
        result = described_class.call(user: user)

        expect(result.ok).to be false
        expect(result.error).to eq("card declined")
        expect(result.mode).to be_nil
      end
    end
  end

  describe ".resume!" do
    it "returns failure when there is no Stripe subscription id" do
      create(:subscription, user: user, pricing_plan: plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)

      result = described_class.resume!(user: user)

      expect(result.ok).to be false
      expect(result.error).to eq("No subscription.")
    end

    it "clears cancel_at_period_end in Stripe" do
      create(
        :subscription,
        user: user,
        pricing_plan: plan,
        status: :active,
        started_at: Time.current,
        stripe_subscription_id: "sub_resume_spec"
      )
      allow(Stripe::Subscription).to receive(:update).with("sub_resume_spec", { cancel_at_period_end: false })

      result = described_class.resume!(user: user)

      expect(result.ok).to be true
      expect(result.mode).to eq(:resumed)
      expect(Stripe::Subscription).to have_received(:update).with("sub_resume_spec", { cancel_at_period_end: false })
    end
  end
end
