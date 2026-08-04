# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureRequest, type: :model do
  let(:user) { create(:user) }
  let(:long_description) { "A clear description that is at least fifty characters long for validation." }

  describe "validations" do
    it "requires title" do
      fr = build(:feature_request, user: user, title: "", description: long_description)
      expect(fr).not_to be_valid
      expect(fr.errors[:title]).to be_present
    end

    it "requires status to be in STATUSES" do
      fr = build(:feature_request, user: user, status: "invalid")
      expect(fr).not_to be_valid
      expect(fr.errors[:status]).to be_present
    end

    it "is valid with required attributes and long description" do
      fr = build(:feature_request, user: user, title: "Add feature", description: long_description)
      expect(fr).to be_valid
    end
  end

  describe "blocked content validation" do
    it "flags title containing blocked word for review (saves with moderation_status pending)" do
      fr = build(:feature_request, user: user, title: "This contains blockedterm", description: long_description)
      expect(fr).to be_valid
      fr.save!
      expect(fr.moderation_status).to eq("pending")
      expect(fr.moderation_triggered_words_list).to include("blockedterm")
    end

    it "flags description containing blocked word for review (saves with moderation_status pending)" do
      fr = build(:feature_request, user: user, title: "Good title", description: "We need this restrictedphrase and more text to hit fifty characters.")
      expect(fr).to be_valid
      fr.save!
      expect(fr.moderation_status).to eq("pending")
      expect(fr.moderation_triggered_words_list).to include("restrictedphrase")
    end

    it "flags severe recruiting blocklist in title even when profanity filter would approve" do
      fr = build(
        :feature_request,
        user: user,
        title: "Please read about nazi history",
        description: long_description
      )
      expect(fr).to be_valid
      fr.save!
      expect(fr.moderation_status).to eq("pending")
      expect(fr.moderation_triggered_words_list).to include("nazi")
    end

    it "merges profanity and severe blocklist hits in triggered words" do
      fr = build(
        :feature_request,
        user: user,
        title: "This contains blockedterm and hostileterm",
        description: long_description
      )
      expect(fr).to be_valid
      fr.save!
      expect(fr.moderation_triggered_words_list).to include("blockedterm", "hostileterm")
    end

    it "allows clean title and description" do
      fr = build(:feature_request, user: user, title: "Add dark mode", description: long_description)
      expect(fr).to be_valid
    end

    it "clears stale moderation metadata when a pending request is edited to clean text" do
      fr = create(:feature_request, user: user, title: "This contains blockedterm", description: long_description)
      expect(fr.reload.moderation_status).to eq("pending")
      expect(fr.moderation_triggered_words).to be_present
      expect(fr.moderation_flagged_at).to be_present

      fr.update!(title: "Polished roadmap request", description: long_description)
      fr.reload

      expect(fr.moderation_status).to eq("approved")
      expect(fr.moderation_triggered_words).to be_nil
      expect(fr.moderation_flagged_at).to be_nil
    end

    it "does not match blocked word inside another word (word boundary)" do
      fr = build(:feature_request, user: user, title: "Class-based design", description: long_description)
      expect(fr).to be_valid
    end
  end

  describe "scopes and visibility" do
    it "visible_to_public includes only approved requests, excludes pending" do
      approved = create(:feature_request, user: user, title: "Add dark mode", description: long_description)
      pending_fr = create(:feature_request, user: user, title: "This contains blockedterm", description: long_description)
      expect(approved.reload.moderation_status).to eq("approved")
      expect(pending_fr.reload.moderation_status).to eq("pending")
      expect(FeatureRequest.visible_to_public).to include(approved)
      expect(FeatureRequest.visible_to_public).not_to include(pending_fr)
    end

    it "excludes soft-deleted requests from visible_to_public and pending_review" do
      approved = create(:feature_request, user: user, title: "Public item", description: long_description)
      flagged = create(:feature_request, user: user, title: "This contains blockedterm", description: long_description)
      expect(flagged.reload.moderation_status).to eq("pending")

      approved.soft_delete!
      flagged.soft_delete!

      expect(FeatureRequest.visible_to_public).not_to include(approved)
      expect(FeatureRequest.pending_review).not_to include(flagged)
      expect(FeatureRequest.with_deleted.find(approved.id).deleted?).to be(true)
    end
  end

  describe "description length" do
    it "requires at least 50 characters" do
      fr = build(:feature_request, user: user, title: "Short desc", description: "Too short")
      expect(fr).not_to be_valid
      expect(fr.errors[:description]).to be_present
    end
  end

  describe "#moderation_triggered_words_list" do
    it "falls back to comma-separated parsing for invalid JSON and strips blanks" do
      fr = build(:feature_request, user: user, title: "Add feature", description: long_description)
      fr.moderation_triggered_words = "bad_word,  another_word,   "

      expect(fr.moderation_triggered_words_list).to eq(%w[bad_word another_word])
    end

    it "parses valid json arrays and strips whitespace and blank entries" do
      fr = build(:feature_request, user: user, title: "Add feature", description: long_description)
      fr.moderation_triggered_words = '[" bad_word ", "", "  "]'

      expect(fr.moderation_triggered_words_list).to eq(%w[bad_word])
    end
  end
end
