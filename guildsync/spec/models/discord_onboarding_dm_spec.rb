require "rails_helper"

RSpec.describe DiscordOnboardingDm, type: :model do
  describe "validations" do
    it "requires discord_user_id" do
      dm = DiscordOnboardingDm.new(context_type: "Guild", context_id: 1, sent_at: Time.current)
      expect(dm).not_to be_valid
      expect(dm.errors[:discord_user_id]).to be_present
    end

    it "requires context_type" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_id: 1, sent_at: Time.current)
      expect(dm).not_to be_valid
      expect(dm.errors[:context_type]).to be_present
    end

    it "requires context_id" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Guild", sent_at: Time.current)
      expect(dm).not_to be_valid
      expect(dm.errors[:context_id]).to be_present
    end

    it "requires sent_at" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Guild", context_id: 1)
      expect(dm).not_to be_valid
      expect(dm.errors[:sent_at]).to be_present
    end

    it "validates context_type inclusion" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Invalid", context_id: 1, sent_at: Time.current)
      expect(dm).not_to be_valid
    end

    it "accepts Guild as context_type" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Guild", context_id: 1, sent_at: Time.current)
      expect(dm).to be_valid
    end

    it "accepts Alliance as context_type" do
      dm = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Alliance", context_id: 1, sent_at: Time.current)
      expect(dm).to be_valid
    end

    it "enforces uniqueness on discord_user_id + context_type + context_id" do
      DiscordOnboardingDm.create!(discord_user_id: "123", context_type: "Guild", context_id: 1, sent_at: Time.current)
      duplicate = DiscordOnboardingDm.new(discord_user_id: "123", context_type: "Guild", context_id: 1, sent_at: Time.current)
      expect(duplicate).not_to be_valid
    end
  end

  describe ".already_sent?" do
    it "returns true when a record exists" do
      DiscordOnboardingDm.create!(discord_user_id: "123", context_type: "Guild", context_id: 1, sent_at: Time.current)
      expect(DiscordOnboardingDm.already_sent?(discord_user_id: "123", context_type: "Guild", context_id: 1)).to be true
    end

    it "returns false when no record exists" do
      expect(DiscordOnboardingDm.already_sent?(discord_user_id: "123", context_type: "Guild", context_id: 1)).to be false
    end
  end

  describe ".record_sent!" do
    it "creates a new record" do
      expect {
        DiscordOnboardingDm.record_sent!(discord_user_id: "123", context_type: "Guild", context_id: 1)
      }.to change(DiscordOnboardingDm, :count).by(1)
    end

    it "sets delivered to true by default" do
      dm = DiscordOnboardingDm.record_sent!(discord_user_id: "123", context_type: "Guild", context_id: 1)
      expect(dm.delivered).to be true
    end

    it "allows setting delivered to false" do
      dm = DiscordOnboardingDm.record_sent!(discord_user_id: "123", context_type: "Guild", context_id: 1, delivered: false)
      expect(dm.delivered).to be false
    end
  end
end
