# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomepageFeatureCard, type: :model do
  it "uses the homepage_feature_cards table" do
    expect(described_class.table_name).to eq("homepage_feature_cards")
  end

  describe "validations and callbacks" do
    it "normalizes slug casing and whitespace before validation" do
      record = described_class.create!(
        slug: "  Member_Management  ",
        title: "Member tools",
        description: "Short marketing description",
        icon_key: described_class::ICON_KEYS.first,
        visible: true,
        position: 0
      )

      expect(record.slug).to eq("member_management")
      expect(record.to_param).to eq("member_management")
    end

    it "rejects unsupported icon keys" do
      record = described_class.new(
        slug: "member_management",
        title: "Member tools",
        description: "Short marketing description",
        icon_key: "not_real",
        visible: true,
        position: 0
      )

      expect(record).not_to be_valid
      expect(record.errors[:icon_key]).to be_present
    end

    it "accepts a synced Font Awesome Free ref" do
      create(:fontawesome_free_icon, style: "solid", icon_name: "key", label: "Key")

      record = described_class.new(
        slug: "fa_card_test",
        title: "FA card",
        description: "Short marketing description",
        icon_key: "fa:solid:key",
        visible: true,
        position: 0
      )

      expect(record).to be_valid
    end

    it "rejects Font Awesome ref missing from the catalog" do
      record = described_class.new(
        slug: "fa_bad_test",
        title: "FA card",
        description: "Short marketing description",
        icon_key: "fa:solid:definitely-missing-icon-xyz",
        visible: true,
        position: 0
      )

      expect(record).not_to be_valid
      expect(record.errors[:icon_key]).to be_present
    end

    it "rejects slug formats outside the marketing URL constraint" do
      record = described_class.new(
        slug: "no-hyphens-allowed",
        title: "Bad slug",
        description: "Short marketing description",
        icon_key: described_class::ICON_KEYS.first,
        visible: true,
        position: 0
      )

      expect(record).not_to be_valid
      expect(record.errors[:slug]).to be_present
    end

    it "requires a unique slug" do
      create(:homepage_feature_card, slug: "alliance_tools")

      duplicate = described_class.new(
        slug: "alliance_tools",
        title: "Other title",
        description: "Short marketing description",
        icon_key: described_class::ICON_KEYS.first,
        visible: true,
        position: 9
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to be_present
    end
  end

  describe "#detail_body_present?" do
    it "is false when rich text is only empty markup" do
      card = create(:homepage_feature_card, slug: "body_probe")
      card.update!(body: "<div class=\"trix-content\"></div>")
      expect(card.reload.detail_body_present?).to be false
    end

    it "is true when plain text content exists" do
      card = create(:homepage_feature_card, slug: "body_probe_2")
      card.update!(body: "<p>Real copy</p>")
      expect(card.reload.detail_body_present?).to be true
    end
  end

  describe "scopes" do
    it "returns visible cards ordered by position then id" do
      visible_late = create(:homepage_feature_card, slug: "visible_late", position: 2, visible: true)
      hidden = create(:homepage_feature_card, slug: "hidden_card", position: 0, visible: false)
      visible_early = create(:homepage_feature_card, slug: "visible_early", position: 1, visible: true)

      expect(described_class.visible.ordered).to eq([ visible_early, visible_late ])
      expect(described_class.visible).not_to include(hidden)
    end
  end
end
