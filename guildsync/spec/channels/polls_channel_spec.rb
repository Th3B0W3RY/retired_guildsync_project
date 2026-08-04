# frozen_string_literal: true

require "rails_helper"

RSpec.describe PollsChannel, type: :channel do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:poll) { create(:poll, guild: guild, creator: owner) }
  let(:member) { create(:user) }

  before do
    create(:guild_member, guild: guild, user: member, role: :member, status: :active)
  end

  it "confirms subscription for an active guild member" do
    stub_connection(current_user: member)
    subscribe(poll_id: poll.id)
    expect(subscription).to be_confirmed
  end

  it "rejects when the user is not a guild member" do
    stub_connection(current_user: create(:user))
    subscribe(poll_id: poll.id)
    expect(subscription).to be_rejected
  end

  it "rejects when poll_id is zero" do
    stub_connection(current_user: member)
    subscribe(poll_id: 0)
    expect(subscription).to be_rejected
  end

  it "rejects when poll does not exist" do
    stub_connection(current_user: member)
    subscribe(poll_id: 999_999_999)
    expect(subscription).to be_rejected
  end
end
