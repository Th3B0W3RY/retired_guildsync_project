# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountDeletion::PurgeService do
  describe "#call_soft" do
    it "teardowns billing rows but does not destroy guild content or tombstone the user" do
      owner = create(:user, email: "soft-#{SecureRandom.hex(4)}@example.com")
      guild = create(:guild, owner: owner)

      allow(Stripe::Subscription).to receive(:retrieve).and_return(double(id: "sub_x", class: Stripe::Subscription))
      allow(Stripe::Subscription).to receive(:cancel)
      allow(Stripe::Customer).to receive(:delete)

      described_class.new(owner).call_soft

      owner.reload
      expect(owner.account_closure_soft_completed_at).to be_present
      expect(owner.account_data_purged_at).to be_nil
      expect(owner.email).to include("@example.com")
      expect(Guild.find_by(id: guild.id)).to be_present
    end
  end

  describe "#call_hard" do
    it "destroys registry scope and tombstones when user still closed" do
      owner = create(:user, email: "hard-#{SecureRandom.hex(4)}@example.com")
      guild = create(:guild, owner: owner)
      owner.update_columns(
        archived: true,
        account_closed_at: 1.day.ago,
        updated_at: Time.current
      )

      allow(Stripe::Subscription).to receive(:retrieve).and_return(double(id: "sub_x", class: Stripe::Subscription))
      allow(Stripe::Subscription).to receive(:cancel)
      allow(Stripe::Customer).to receive(:delete)

      described_class.new(owner).call_hard

      owner.reload
      expect(owner.account_data_purged_at).to be_present
      expect(owner.email).to eq("deleted+#{owner.id}@guildsync.invalid")
      expect(Guild.find_by(id: guild.id)).to be_nil
    end
  end
end
