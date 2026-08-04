# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomepageFeatureCards::EnsureFromI18n do
  describe ".call" do
    it "creates all ICON_KEYS when the table is empty" do
      expect { described_class.call }
        .to change(HomepageFeatureCard, :count).by(HomepageFeatureCard::ICON_KEYS.size)
      expect(HomepageFeatureCard.pluck(:slug)).to match_array(HomepageFeatureCard::ICON_KEYS)
    end

    it "is idempotent — calling twice does not create duplicate records" do
      described_class.call
      count_after_first = HomepageFeatureCard.count
      expect { described_class.call }.not_to change(HomepageFeatureCard, :count)
      expect(HomepageFeatureCard.count).to eq(count_after_first)
    end

    it "does not overwrite existing rows — admin-edited title is preserved" do
      slug = HomepageFeatureCard::ICON_KEYS.first
      HomepageFeatureCard.create!(
        slug: slug,
        title: "Custom Admin Title",
        description: "Custom admin description",
        icon_key: slug,
        position: 0,
        visible: true
      )

      described_class.call

      expect(HomepageFeatureCard.find_by!(slug: slug).title).to eq("Custom Admin Title")
    end

    it "only creates missing slugs when some already exist" do
      existing_slug = HomepageFeatureCard::ICON_KEYS.first
      HomepageFeatureCard.create!(
        slug: existing_slug,
        title: "Already Here",
        description: "Exists",
        icon_key: existing_slug,
        position: 0,
        visible: true
      )

      expect { described_class.call }
        .to change(HomepageFeatureCard, :count).by(HomepageFeatureCard::ICON_KEYS.size - 1)
    end

    it "assigns sequential positions starting after the highest existing position" do
      existing_slug = HomepageFeatureCard::ICON_KEYS.first
      HomepageFeatureCard.create!(
        slug: existing_slug,
        title: "Existing",
        description: "Exists",
        icon_key: existing_slug,
        position: 10,
        visible: true
      )

      described_class.call

      new_positions = HomepageFeatureCard.where.not(slug: existing_slug).pluck(:position).sort
      expect(new_positions.min).to eq(11)
      expect(new_positions).to eq((11..(11 + HomepageFeatureCard::ICON_KEYS.size - 2)).to_a)
    end

    it "fills titles from EN i18n for newly created cards" do
      described_class.call

      HomepageFeatureCard::ICON_KEYS.each do |slug|
        expected_title = I18n.t("home.landing.features_grid.#{slug}.title", locale: :en)
        expect(HomepageFeatureCard.find_by!(slug: slug).title).to eq(expected_title)
      end
    end
  end
end
