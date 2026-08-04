# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountDeletionJob, type: :job do
  it "runs soft purge, keeps owned guild graph and identity, and schedules hard purge" do
    owner = create(:user, email: "purgeowner-#{SecureRandom.hex(4)}@example.com")
    guild = create(:guild, owner: owner)
    user = guild.owner
    closed_at = Time.zone.parse("2026-05-01 12:00:00")
    user.update_columns(
      archived: true,
      account_closed_at: closed_at,
      account_deletion_started_at: closed_at,
      updated_at: Time.current
    )

    allow(Stripe::Subscription).to receive(:retrieve).and_return(double(id: "sub_test", class: Stripe::Subscription))
    allow(Stripe::Subscription).to receive(:cancel)
    allow(Stripe::Customer).to receive(:delete)
    allow(AccountHardPurgeJob).to receive(:perform_at)

    described_class.new.perform(user.id)

    user.reload
    expect(user.email).to match(/\Apurgeowner-.+@example\.com\z/)
    expect(user.account_closure_soft_completed_at).to be_present
    expect(user.account_data_purged_at).to be_nil
    expect(Guild.find_by(id: guild.id)).to be_present

    expected_run = closed_at + SoftDeletable::RETENTION_PERIOD
    expect(AccountHardPurgeJob).to have_received(:perform_at) do |run_at, uid|
      expect(uid).to eq(user.id)
      expect(run_at).to be_within(2.seconds).of(expected_run)
    end
  end

  it "no-ops when soft close already completed" do
    user = create(:user, email: "softdone@example.com")
    user.update_columns(
      account_closure_soft_completed_at: Time.current,
      updated_at: Time.current
    )

    expect(AccountDeletion::PurgeService).not_to receive(:new)
    described_class.new.perform(user.id)
  end

  it "no-ops when hard purge already completed" do
    user = create(:user, email: "tomb@example.com")
    user.update_columns(
      account_data_purged_at: Time.current,
      updated_at: Time.current
    )

    expect(AccountDeletion::PurgeService).not_to receive(:new)
    described_class.new.perform(user.id)
  end
end
