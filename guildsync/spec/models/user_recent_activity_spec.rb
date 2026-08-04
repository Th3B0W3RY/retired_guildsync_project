# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRecentActivity, type: :model do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  describe "associations" do
    it "belongs to user" do
      activity = create(:user_recent_activity, user: user)
      expect(activity.user).to eq(user)
    end

    it "belongs to subject (optional)" do
      activity = create(:user_recent_activity, user: user, subject: guild)
      expect(activity.subject).to eq(guild)
    end

    it "allows subject to be nil" do
      activity = create(:user_recent_activity, user: user, subject: nil)
      expect(activity.subject).to be_nil
    end
  end

  describe "validations" do
    it "requires path" do
      activity = build(:user_recent_activity, user: user, path: nil)
      expect(activity).not_to be_valid
      expect(activity.errors[:path]).to be_present
    end

    it "requires label" do
      activity = build(:user_recent_activity, user: user, label: nil)
      expect(activity).not_to be_valid
      expect(activity.errors[:label]).to be_present
    end

    it "rejects path longer than 2048" do
      activity = build(:user_recent_activity, user: user, path: "a" * 2049)
      expect(activity).not_to be_valid
      expect(activity.errors[:path]).to be_present
    end

    it "rejects label longer than 500" do
      activity = build(:user_recent_activity, user: user, label: "a" * 501)
      expect(activity).not_to be_valid
      expect(activity.errors[:label]).to be_present
    end

    it "allows link_path to be nil" do
      activity = build(:user_recent_activity, user: user, link_path: nil)
      expect(activity).to be_valid
    end

    it "rejects link_path longer than 2048" do
      activity = build(:user_recent_activity, user: user, link_path: "a" * 2049)
      expect(activity).not_to be_valid
      expect(activity.errors[:link_path]).to be_present
    end
  end

  describe "#linkable?" do
    it "is true when link_path is present" do
      activity = build(:user_recent_activity, user: user, link_path: "/dashboard")
      expect(activity).to be_linkable
    end

    it "is false when link_path is blank" do
      activity = build(:user_recent_activity, user: user, link_path: nil)
      expect(activity).not_to be_linkable
    end
  end

  describe "scopes" do
    it "orders by created_at desc (recent_first)" do
      a1 = create(:user_recent_activity, user: user, path: "/a", label: "A", created_at: 2.days.ago)
      a2 = create(:user_recent_activity, user: user, path: "/b", label: "B", created_at: 1.day.ago)
      expect(user.user_recent_activities.recent_first.to_a).to eq([ a2, a1 ])
    end
  end

  describe "pruning (keep only last 10)" do
    it "keeps only the 10 most recent activities per user after create" do
      12.times do |i|
        UserRecentActivity.create!(user: user, path: "/path#{i}", label: "Label #{i}")
      end
      expect(user.user_recent_activities.count).to eq(10)
      labels = user.user_recent_activities.recent_first.pluck(:label)
      expect(labels).to include("Label 11", "Label 10")
      expect(labels).not_to include("Label 0", "Label 1")
    end

    it "does not delete rows when the keep-id list is empty (avoids unrestricted DELETE)" do
      u = create(:user)
      create(:user_recent_activity, user: u, path: "/first", label: "First")
      rel = u.user_recent_activities
      tail = instance_double(ActiveRecord::Relation)
      allow(tail).to receive(:pluck).with(:id).and_return([])
      mid = instance_double(ActiveRecord::Relation)
      allow(mid).to receive(:limit).with(UserRecentActivity::MAX_RECENT).and_return(tail)
      allow(rel).to receive(:recent_first).and_return(mid)
      allow(u).to receive(:user_recent_activities).and_return(rel)

      expect {
        UserRecentActivity.create!(user: u, path: "/second", label: "Second")
      }.to change { UserRecentActivity.where(user: u).count }.from(1).to(2)
    end
  end
end
