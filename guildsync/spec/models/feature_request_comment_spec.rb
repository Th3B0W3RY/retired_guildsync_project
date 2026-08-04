# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureRequestComment, type: :model do
  let(:user) { create(:user) }
  let(:feature_request) { create(:feature_request, user: user) }

  describe "blocked content validation" do
    it "flags body containing blocked word for review (saves with moderation_status pending)" do
      comment = build(:feature_request_comment, feature_request: feature_request, user: user, body: "This contains blockedterm")
      expect(comment).to be_valid
      comment.save!
      expect(comment.moderation_status).to eq("pending")
      expect(comment.moderation_triggered_words_list).to include("blockedterm")
    end

    it "flags severe recruiting blocklist in body when profanity filter would approve" do
      body = "Educational note mentioning hitler in context needs enough characters."
      comment = build(:feature_request_comment, feature_request: feature_request, user: user, body: body)
      expect(comment).to be_valid
      comment.save!
      expect(comment.moderation_status).to eq("pending")
      expect(comment.moderation_triggered_words_list).to include("hitler")
    end

    it "allows clean body" do
      comment = build(:feature_request_comment, feature_request: feature_request, user: user, body: "Great idea, +1")
      expect(comment).to be_valid
    end

    it "clears stale moderation metadata when a pending comment is edited to clean text" do
      comment = create(:feature_request_comment, feature_request: feature_request, user: user, body: "This contains blockedterm")
      expect(comment.reload.moderation_status).to eq("pending")
      expect(comment.moderation_triggered_words).to be_present
      expect(comment.moderation_flagged_at).to be_present

      comment.update!(body: "Constructive feedback with no banned terms")
      comment.reload

      expect(comment.moderation_status).to eq("approved")
      expect(comment.moderation_triggered_words).to be_nil
      expect(comment.moderation_flagged_at).to be_nil
    end
  end

  describe "#can_delete_by?" do
    it "allows admin email match regardless of case" do
      admin_user = create(:user, email: "Admin@Example.com")
      original_admins = ENV["ADMIN_EMAILS"]
      ENV["ADMIN_EMAILS"] = "admin@example.com"

      expect(build(:feature_request_comment, feature_request: feature_request, user: user).can_delete_by?(admin_user)).to be(true)
    ensure
      ENV["ADMIN_EMAILS"] = original_admins
    end
  end

  describe "#moderation_triggered_words_list" do
    it "falls back to comma-separated parsing for invalid JSON and strips blanks" do
      comment = build(:feature_request_comment, feature_request: feature_request, user: user, body: "Great idea, +1")
      comment.moderation_triggered_words = "flag_one, flag_two,   "

      expect(comment.moderation_triggered_words_list).to eq(%w[flag_one flag_two])
    end

    it "parses valid json arrays, trims entries, and rejects blanks" do
      comment = build(:feature_request_comment, feature_request: feature_request, user: user, body: "Great idea, +1")
      comment.moderation_triggered_words = "[\" flag_one \", \"flag_two\", \"\", \"   \"]"

      expect(comment.moderation_triggered_words_list).to eq(%w[flag_one flag_two])
    end
  end

  describe "soft delete lifecycle" do
    it "supports concern-based soft delete and restore helpers" do
      comment = create(:feature_request_comment, feature_request: feature_request, user: user, body: "Keep this around")

      expect { comment.soft_delete! }.to change { comment.reload.deleted? }.from(false).to(true)
      expect(FeatureRequestComment.find_by(id: comment.id)).to be_nil
      expect(FeatureRequestComment.with_deleted.find(comment.id)).to be_deleted

      expect { comment.restore! }.to change { comment.reload.deleted? }.from(true).to(false)
      expect(FeatureRequestComment.find(comment.id)).to be_present
    end
  end
end
