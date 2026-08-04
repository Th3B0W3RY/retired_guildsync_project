# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeArchivedGuildsJob, type: :job do
  it "purges only retention-eligible archived guilds" do
    owner = create(:user, :discord_auth)
    ready = create(:guild, owner: owner, archived_at: 2.years.ago, scheduled_purge_at: 1.day.ago)
    waiting = create(:guild, owner: owner, archived_at: 2.days.ago, scheduled_purge_at: 1.month.from_now)
    active = create(:guild, owner: owner)

    expect {
      described_class.perform_now
    }.to change(Guild, :count).by(-1)

    expect(Guild.exists?(ready.id)).to be(false)
    expect(Guild.exists?(waiting.id)).to be(true)
    expect(Guild.exists?(active.id)).to be(true)
  end

  it "logs a summary when guilds are purged" do
    owner = create(:user, :discord_auth)
    create(:guild, owner: owner, archived_at: 2.years.ago, scheduled_purge_at: 1.day.ago)

    expect(Rails.logger).to receive(:info).with(/\[PurgeArchivedGuildsJob\] Purged 1 archived guild/)
    described_class.perform_now
  end
end
