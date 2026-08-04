# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentModeration::FilterService do
  let(:user) { create(:user) }

  before do
    BlockedContentFilter.reset!
    Rails.cache.clear
    create(:blocked_word, word: "blockedterm", category: "profanity")
    create(:blocked_word, word: "restrictedphrase", category: "profanity")
  end

  after { BlockedContentFilter.reset! }

  describe "#process" do
    it "returns pending with triggered words when content contains blocked word" do
      service = described_class.new("this has blockedterm in it", content_type: "Test", user: user)
      result = service.process
      expect(result[:status]).to eq(:pending)
      expect(result[:triggered_words]).to include("blockedterm")
      expect(result[:message]).to be_present
    end

    it "returns approved when content is clean" do
      service = described_class.new("this is clean content", content_type: "Test", user: user)
      result = service.process
      expect(result[:status]).to eq(:approved)
      expect(result).not_to have_key(:triggered_words)
    end

    it "bypasses when user responds to trusted? with true" do
      trusted_user = double("User", trusted?: true)
      allow(trusted_user).to receive(:respond_to?).with(:trusted?).and_return(true)
      service = described_class.new("this has blockedterm in it", content_type: "Test", user: trusted_user)
      result = service.process
      expect(result[:status]).to eq(:approved)
      expect(result[:bypass]).to be true
    end

    it "flags when user is nil and content has blocked word" do
      service = described_class.new("blockedterm content", content_type: "Test", user: nil)
      result = service.process
      expect(result[:status]).to eq(:pending)
      expect(result[:triggered_words]).to include("blockedterm")
    end
  end

  describe "#scan_for_blocked_words" do
    it "returns list of triggered words" do
      service = described_class.new("test", content_type: "Test", user: nil)
      expect(service.scan_for_blocked_words("this has restrictedphrase in it")).to include("restrictedphrase")
      expect(service.scan_for_blocked_words("clean")).to eq([])
    end
  end
end
