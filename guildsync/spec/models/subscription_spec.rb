# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription, type: :model do
  let!(:free_plan) do
    create(:pricing_plan,
           name: "Free",
           price: 0,
           price_display: "$0",
           period: "forever",
           max_guilds: 1,
           max_members_per_guild: 10,
           active: true,
           display_order: 1)
  end

  let(:user) { create(:user) }

  describe "validations" do
    it "requires started_at" do
      subscription = build(:subscription, user: user, started_at: nil)
      expect(subscription).not_to be_valid
      expect(subscription.errors[:started_at]).to be_present
    end

    it "validates expires_at is after started_at" do
      subscription = build(:subscription,
                          user: user,
                          started_at: 1.day.from_now,
                          expires_at: 1.day.ago)
      expect(subscription).not_to be_valid
      expect(subscription.errors[:expires_at]).to be_present
    end
  end

  describe "associations" do
    it "belongs to a user" do
      subscription = create(:subscription, user: user, pricing_plan: free_plan)
      expect(subscription.user).to eq(user)
    end

    it "belongs to a pricing plan" do
      subscription = create(:subscription, user: user, pricing_plan: free_plan)
      expect(subscription.pricing_plan).to eq(free_plan)
    end
  end

  describe "#refund_eligible?" do
    it "is false when first_paid_invoice_at is nil" do
      sub = create(:subscription, user: user, pricing_plan: free_plan, first_paid_invoice_at: nil)
      expect(sub.refund_eligible?).to be false
    end

    it "is true within three days of first paid invoice" do
      sub = create(:subscription, user: user, pricing_plan: free_plan, first_paid_invoice_at: 1.day.ago)
      expect(sub.refund_eligible?).to be true
    end

    it "is false after three days from first paid invoice" do
      sub = create(:subscription, user: user, pricing_plan: free_plan, first_paid_invoice_at: 4.days.ago)
      expect(sub.refund_eligible?).to be false
    end
  end

end

