# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserActivityTracker do
  let(:user) { create(:user) }

  describe ".record" do
    it "persists link_path when provided" do
      described_class.record(user: user, path: "/dashboard", label: "Dashboard", link_path: "/dashboard")
      activity = user.user_recent_activities.recent_first.first
      expect(activity.link_path).to eq("/dashboard")
      expect(activity).to be_linkable
    end

    it "stores a nil link_path for non-linkable actions" do
      described_class.record(user: user, path: "/auth/discord/callback", label: "Signed in with Discord")
      activity = user.user_recent_activities.recent_first.first
      expect(activity.link_path).to be_nil
      expect(activity).not_to be_linkable
    end

    it "ignores blank user, path, or label" do
      expect {
        described_class.record(user: user, path: "/x", label: "")
      }.not_to change(UserRecentActivity, :count)
    end
  end
end
