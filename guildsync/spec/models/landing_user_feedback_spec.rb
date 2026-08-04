# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingUserFeedback, type: :model do
  describe "validations" do
    it "requires rich text body" do
      record = described_class.new(visible: true, position: 0)
      expect(record).not_to be_valid
      expect(record.errors[:body]).to include("can't be blank")
    end

    it "blocks creation when at the homepage entry cap" do
      described_class::MAX_ENTRIES.times { create(:landing_user_feedback) }

      extra = described_class.new(visible: true, position: 999)
      extra.body = "<p>One too many</p>"

      expect(extra).not_to be_valid
      expect(extra.errors[:base]).to be_present
    end

    it "allows a new active entry after soft-deleting one at the cap" do
      described_class::MAX_ENTRIES.times { create(:landing_user_feedback) }
      last = described_class.ordered.last
      last.soft_delete!

      replacement = described_class.new(visible: true, position: 999)
      replacement.body = "<p>Replacement after soft delete</p>"

      expect(replacement).to be_valid
    end

    it "allows updates when the entry cap has already been reached" do
      record = create(:landing_user_feedback)
      (described_class::MAX_ENTRIES - 1).times { create(:landing_user_feedback) }

      record.body = "<p>Updated copy after reaching the cap.</p>"

      expect(record).to be_valid
    end
  end

  describe "scopes" do
    it "returns only visible entries ordered by position then id" do
      visible_late = create(:landing_user_feedback, position: 2, visible: true)
      hidden = create(:landing_user_feedback, position: 0, visible: false)
      visible_early = create(:landing_user_feedback, position: 1, visible: true)

      expect(described_class.visible.ordered).to eq([ visible_early, visible_late ])
      expect(described_class.visible).not_to include(hidden)
    end
  end
end
