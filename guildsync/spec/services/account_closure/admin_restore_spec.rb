# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountClosure::AdminRestore do
  describe ".eligible?" do
    it "is true for a closed account inside retention without hard purge" do
      user = create(:user)
      user.update_columns(
        archived: true,
        account_closed_at: 1.day.ago,
        account_deletion_started_at: 1.day.ago,
        account_closure_soft_completed_at: 1.day.ago,
        account_data_purged_at: nil,
        updated_at: Time.current
      )
      expect(described_class.eligible?(user)).to be true
    end

    it "is false when hard purge completed" do
      user = create(:user)
      user.update_columns(
        archived: true,
        account_closed_at: 1.day.ago,
        account_data_purged_at: Time.current,
        updated_at: Time.current
      )
      expect(described_class.eligible?(user)).to be false
    end

    it "is false when outside retention window" do
      user = create(:user)
      user.update_columns(
        archived: true,
        account_closed_at: 7.months.ago,
        account_data_purged_at: nil,
        updated_at: Time.current
      )
      expect(described_class.eligible?(user)).to be false
    end
  end

  describe "#call" do
    it "clears closure flags when eligible" do
      user = create(:user, email: "restore-#{SecureRandom.hex(4)}@example.com")
      user.update_columns(
        archived: true,
        account_closed_at: 1.week.ago,
        account_deletion_started_at: 1.week.ago,
        account_closure_soft_completed_at: 1.week.ago,
        updated_at: Time.current
      )

      result = described_class.new(user).call
      expect(result.ok?).to be true

      user.reload
      expect(user.archived).to be false
      expect(user.account_closed_at).to be_nil
      expect(user.account_deletion_started_at).to be_nil
      expect(user.account_closure_soft_completed_at).to be_nil
    end

    it "returns error when ineligible" do
      user = create(:user)
      user.update_columns(account_data_purged_at: Time.current, updated_at: Time.current)
      result = described_class.new(user).call
      expect(result.ok?).to be false
      expect(result.error_key).to eq(:hard_purged)
    end
  end
end
