# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountHardPurgeJob, type: :job do
  it "tombstones user and destroys owned guild graph when closure still active" do
    owner = create(:user, email: "hardowner-#{SecureRandom.hex(4)}@example.com")
    guild = create(:guild, owner: owner)
    user = guild.owner
    user.update_columns(
      archived: true,
      account_closed_at: 2.weeks.ago,
      account_deletion_started_at: 2.weeks.ago,
      account_closure_soft_completed_at: 2.weeks.ago,
      updated_at: Time.current
    )

    allow(Stripe::Subscription).to receive(:retrieve).and_return(double(id: "sub_test", class: Stripe::Subscription))
    allow(Stripe::Subscription).to receive(:cancel)
    allow(Stripe::Customer).to receive(:delete)

    described_class.new.perform(user.id)

    user.reload
    expect(user.email).to eq("deleted+#{user.id}@guildsync.invalid")
    expect(user.username).to eq("deleted_#{user.id}")
    expect(user.account_data_purged_at).to be_present
    expect(Guild.find_by(id: guild.id)).to be_nil
  end

  it "no-ops when user was restored (closure cleared)" do
    user = create(:user, email: "restored-#{SecureRandom.hex(4)}@example.com")
    user.update_columns(
      archived: false,
      account_closed_at: nil,
      account_deletion_started_at: nil,
      account_closure_soft_completed_at: nil,
      updated_at: Time.current
    )

    expect(AccountDeletion::PurgeService).not_to receive(:new)
    described_class.new.perform(user.id)
  end

  it "no-ops when hard purge already completed" do
    user = create(:user, email: "done-#{SecureRandom.hex(4)}@example.com")
    user.update_columns(
      account_closed_at: 1.month.ago,
      account_data_purged_at: Time.current,
      updated_at: Time.current
    )

    expect(AccountDeletion::PurgeService).not_to receive(:new)
    described_class.new.perform(user.id)
  end
end
