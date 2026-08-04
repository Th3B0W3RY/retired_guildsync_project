# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModerationFlag, type: :model do
  let(:user) { create(:user) }
  let(:feature_request) { create(:feature_request, user: user) }

  describe "validations" do
    it "validates status inclusion" do
      flag = build(:moderation_flag, flaggable: feature_request, status: "invalid")
      expect(flag).not_to be_valid
      expect(flag.errors[:status]).to be_present
    end

    it "accepts pending, resolved, dismissed" do
      %w[pending resolved dismissed].each do |status|
        flag = build(:moderation_flag, flaggable: feature_request, status: status)
        expect(flag).to be_valid
      end
    end
  end

  describe "scopes" do
    it "pending returns only pending flags" do
      pending_flag = create(:moderation_flag, flaggable: feature_request, status: "pending")
      create(:moderation_flag, flaggable: feature_request, status: "resolved")
      expect(ModerationFlag.pending).to include(pending_flag)
      expect(ModerationFlag.pending.count).to eq(1)
    end
  end
end
