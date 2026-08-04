# frozen_string_literal: true

require "rails_helper"

RSpec.describe SiteSetting, type: :model do
  describe "validations" do
    it "requires a key" do
      setting = SiteSetting.new(value: "test")
      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to include("can't be blank")
    end

    it "requires a value" do
      setting = SiteSetting.new(key: "test")
      expect(setting).not_to be_valid
      expect(setting.errors[:value]).to include("can't be blank")
    end

    it "enforces unique keys" do
      SiteSetting.create!(key: "test_key", value: "one")
      duplicate = SiteSetting.new(key: "test_key", value: "two")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include("has already been taken")
    end
  end

  describe ".get" do
    it "returns the stored value" do
      SiteSetting.create!(key: "my_key", value: "my_value")
      expect(SiteSetting.get("my_key")).to eq("my_value")
    end

    it "falls back to DEFAULTS when no record exists" do
      expect(SiteSetting.get("release_notes_url")).to eq(SiteSetting::DEFAULTS["release_notes_url"])
      expect(SiteSetting.get("flash_toast_duration_ms")).to eq(SiteSetting::DEFAULTS["flash_toast_duration_ms"])
    end

    it "returns nil for unknown keys with no default" do
      expect(SiteSetting.get("nonexistent")).to be_nil
    end

    it "falls back to DEFAULTS on database errors" do
      allow(SiteSetting).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid)
      expect(SiteSetting.get("release_notes_url")).to eq(SiteSetting::DEFAULTS["release_notes_url"])
    end
  end

  describe ".set" do
    it "creates a new record" do
      expect { SiteSetting.set("new_key", "val") }.to change(SiteSetting, :count).by(1)
      expect(SiteSetting.get("new_key")).to eq("val")
    end

    it "updates an existing record" do
      SiteSetting.set("key", "first")
      expect { SiteSetting.set("key", "second") }.not_to change(SiteSetting, :count)
      expect(SiteSetting.get("key")).to eq("second")
    end
  end

  describe ".landing_feedback_carousel_interval_ms" do
    it "returns default when unconfigured" do
      expect(SiteSetting.landing_feedback_carousel_interval_ms).to eq(SiteSetting::LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS)
    end

    it "returns stored value when in range" do
      SiteSetting.set("landing_feedback_carousel_interval_ms", "10000")
      expect(SiteSetting.landing_feedback_carousel_interval_ms).to eq(10_000)
    end

    it "returns default when below minimum" do
      SiteSetting.set("landing_feedback_carousel_interval_ms", "500")
      expect(SiteSetting.landing_feedback_carousel_interval_ms).to eq(SiteSetting::LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS)
    end

    it "returns default when above maximum" do
      SiteSetting.set("landing_feedback_carousel_interval_ms", "120000")
      expect(SiteSetting.landing_feedback_carousel_interval_ms).to eq(SiteSetting::LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS)
    end

    it "returns default when not an integer" do
      SiteSetting.set("landing_feedback_carousel_interval_ms", "abc")
      expect(SiteSetting.landing_feedback_carousel_interval_ms).to eq(SiteSetting::LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS)
    end
  end

  describe ".flash_toast_duration_ms" do
    it "returns the stored value when in range" do
      SiteSetting.set("flash_toast_duration_ms", "2000")
      expect(SiteSetting.flash_toast_duration_ms).to eq(2000)
    end

    it "returns default when value is out of range" do
      SiteSetting.set("flash_toast_duration_ms", "100")
      expect(SiteSetting.flash_toast_duration_ms).to eq(SiteSetting::FLASH_TOAST_DURATION_DEFAULT_MS)
    end

    it "returns default when value is not an integer" do
      SiteSetting.set("flash_toast_duration_ms", "abc")
      expect(SiteSetting.flash_toast_duration_ms).to eq(SiteSetting::FLASH_TOAST_DURATION_DEFAULT_MS)
    end
  end

  describe ".release_notes_url" do
    it "delegates to .get with the correct key" do
      SiteSetting.set("release_notes_url", "https://custom.example.com")
      expect(SiteSetting.release_notes_url).to eq("https://custom.example.com")
    end

    it "returns the default Zoho URL when unconfigured" do
      expect(SiteSetting.release_notes_url).to eq(SiteSetting::DEFAULTS["release_notes_url"])
    end
  end

  describe "homepage footer url readers" do
    it "returns the default documentation url when unconfigured" do
      expect(SiteSetting.homepage_footer_documentation_url).to eq(SiteSetting::DEFAULTS["homepage_footer_documentation_url"])
    end

    it "returns the stored contact url when configured" do
      SiteSetting.set("homepage_footer_contact_url", "https://contact.example.test")
      expect(SiteSetting.homepage_footer_contact_url).to eq("https://contact.example.test")
    end

    it "returns the stored discord url when configured" do
      SiteSetting.set("homepage_footer_discord_url", "https://discord.gg/guildsync")
      expect(SiteSetting.homepage_footer_discord_url).to eq("https://discord.gg/guildsync")
    end
  end

  describe ".error_batch_cadence_hours" do
    it "returns the stored value when it is a valid integer" do
      SiteSetting.set("error_batch_cadence_hours", "48")
      expect(SiteSetting.error_batch_cadence_hours).to eq(48)
    end

    it "returns ERROR_BATCH_CADENCE_DEFAULT before any record is created" do
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_DEFAULT)
    end

    it "returns ERROR_BATCH_CADENCE_DEFAULT when value is below minimum" do
      SiteSetting.set("error_batch_cadence_hours", "0")
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_DEFAULT)
    end

    it "returns ERROR_BATCH_CADENCE_DEFAULT when value exceeds maximum" do
      SiteSetting.set("error_batch_cadence_hours", "9999")
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_DEFAULT)
    end

    it "returns ERROR_BATCH_CADENCE_DEFAULT when value is not an integer" do
      SiteSetting.set("error_batch_cadence_hours", "daily")
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_DEFAULT)
    end

    it "accepts the minimum boundary value" do
      SiteSetting.set("error_batch_cadence_hours", SiteSetting::ERROR_BATCH_CADENCE_MIN.to_s)
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_MIN)
    end

    it "accepts the maximum boundary value" do
      SiteSetting.set("error_batch_cadence_hours", SiteSetting::ERROR_BATCH_CADENCE_MAX.to_s)
      expect(SiteSetting.error_batch_cadence_hours).to eq(SiteSetting::ERROR_BATCH_CADENCE_MAX)
    end
  end

  describe ".error_immediate_severities" do
    it "returns the default [\"urgent\"] before any record is created" do
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
    end

    it "returns stored valid severities" do
      SiteSetting.set("error_immediate_severities", '["urgent","high"]')
      expect(SiteSetting.error_immediate_severities).to contain_exactly("urgent", "high")
    end

    it "silently drops values that are not valid ErrorLog severities" do
      SiteSetting.set("error_immediate_severities", '["urgent","bogus","also_bad"]')
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
    end

    it "returns an empty array when configured to [] (all errors batched)" do
      SiteSetting.set("error_immediate_severities", "[]")
      expect(SiteSetting.error_immediate_severities).to eq([])
    end

    it "returns the default when JSON is malformed" do
      SiteSetting.set("error_immediate_severities", "not_json{{}}")
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
    end

    it "returns the default when JSON parses to a non-array" do
      SiteSetting.set("error_immediate_severities", "{}")
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])

      SiteSetting.set("error_immediate_severities", '"high"')
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
    end

    it "coerces array elements to strings before filtering" do
      SiteSetting.set("error_immediate_severities", '["urgent",1]')
      expect(SiteSetting.error_immediate_severities).to eq(["urgent"])
    end
  end

  describe ".error_notify_discord_usernames" do
    it "returns the default list before any record is created" do
      expect(SiteSetting.error_notify_discord_usernames).to eq(%w[thecinopewpew breezybeast4])
    end

    it "returns stored usernames when JSON is a string array" do
      SiteSetting.set("error_notify_discord_usernames", '["ops_one","ops_two"]')
      expect(SiteSetting.error_notify_discord_usernames).to eq(%w[ops_one ops_two])
    end

    it "returns an empty array when configured to []" do
      SiteSetting.set("error_notify_discord_usernames", "[]")
      expect(SiteSetting.error_notify_discord_usernames).to eq([])
    end

    it "returns the default when JSON is malformed" do
      SiteSetting.set("error_notify_discord_usernames", "not json")
      expect(SiteSetting.error_notify_discord_usernames).to eq(%w[thecinopewpew breezybeast4])
    end

    it "returns the default when JSON parses to a non-array" do
      SiteSetting.set("error_notify_discord_usernames", "{}")
      expect(SiteSetting.error_notify_discord_usernames).to eq(%w[thecinopewpew breezybeast4])
    end

    it "strips whitespace and drops blank entries" do
      SiteSetting.set("error_notify_discord_usernames", '["  alice  ", "", "bob"]')
      expect(SiteSetting.error_notify_discord_usernames).to eq(%w[alice bob])
    end
  end
end
