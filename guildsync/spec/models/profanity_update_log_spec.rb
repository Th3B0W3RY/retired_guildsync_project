# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfanityUpdateLog, type: :model do
  describe "validations" do
    it "requires timestamp" do
      log = build(:profanity_update_log, timestamp: nil)
      expect(log).not_to be_valid
      expect(log.errors[:timestamp]).to be_present
    end
  end

  describe ".recent" do
    it "returns last 10 by created_at desc" do
      logs = 12.times.map { create(:profanity_update_log) }
      recent = described_class.recent
      expect(recent.count).to eq(10)
      expect(recent.first).to eq(logs.last)
    end
  end

  describe ".health_status" do
    it "returns unknown when no logs" do
      expect(described_class.health_status).to eq({ status: "unknown" })
    end

    it "returns healthy_updated when words were added or removed" do
      create(:profanity_update_log, new_words_added: 5, words_removed: 0, total_words: 105, error_messages: [])
      expect(described_class.health_status[:status]).to eq("healthy_updated")
    end

    it "returns healthy_stable when no change" do
      create(:profanity_update_log, new_words_added: 0, words_removed: 0, total_words: 100, error_messages: [])
      expect(described_class.health_status[:status]).to eq("healthy_stable")
    end

    it "returns degraded when errors present" do
      create(:profanity_update_log, error_messages: [ "Source X failed" ])
      status = described_class.health_status
      expect(status[:status]).to eq("degraded")
      expect(status[:errors]).to include("Source X failed")
    end
  end
end
