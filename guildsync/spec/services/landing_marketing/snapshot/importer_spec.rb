# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingMarketing::Snapshot::Importer do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/landing_marketing/marketing_snapshot_minimal.yml") }

  it "raises when the snapshot file is missing" do
    expect do
      described_class.new(path: Rails.root.join("spec/fixtures/files/landing_marketing/no_such_file.yml")).call
    end.to raise_error(described_class::Error, /Snapshot file missing/)
  end

  it "raises when version is not supported" do
    Tempfile.create(%w[snapshot .yml]) do |f|
      f.write(YAML.dump({
        "version" => 999,
        "homepage_feature_cards" => [],
        "landing_comparison_tables" => []
      }))
      f.flush
      expect do
        described_class.new(path: f.path).call
      end.to raise_error(described_class::Error, /Unsupported snapshot version/)
    end
  end

  describe "malformed snapshot validation" do
    it "raises when homepage_feature_cards key is missing" do
      Tempfile.create(%w[snapshot .yml]) do |f|
        f.write(YAML.dump({ "version" => 1, "landing_comparison_tables" => [] }))
        f.flush
        expect do
          described_class.new(path: f.path).call
        end.to raise_error(described_class::Error, /missing required key 'homepage_feature_cards'/)
      end
    end

    it "raises when landing_comparison_tables key is missing" do
      Tempfile.create(%w[snapshot .yml]) do |f|
        f.write(YAML.dump({ "version" => 1, "homepage_feature_cards" => [] }))
        f.flush
        expect do
          described_class.new(path: f.path).call
        end.to raise_error(described_class::Error, /missing required key 'landing_comparison_tables'/)
      end
    end

    it "raises when homepage_feature_cards contains a non-Hash element" do
      Tempfile.create(%w[snapshot .yml]) do |f|
        f.write(YAML.dump({ "version" => 1, "homepage_feature_cards" => [ "not_a_hash" ], "landing_comparison_tables" => [] }))
        f.flush
        expect do
          described_class.new(path: f.path).call
        end.to raise_error(described_class::Error, /homepage_feature_cards.*array of objects/i)
      end
    end

    it "raises when landing_comparison_tables contains a non-Hash element" do
      Tempfile.create(%w[snapshot .yml]) do |f|
        f.write(YAML.dump({ "version" => 1, "homepage_feature_cards" => [], "landing_comparison_tables" => [ 42 ] }))
        f.flush
        expect do
          described_class.new(path: f.path).call
        end.to raise_error(described_class::Error, /landing_comparison_tables.*array of objects/i)
      end
    end

    it "does NOT destroy existing records when shape validation fails" do
      HomepageFeatureCard.create!(
        slug: "member_management", title: "Keep Me", description: "desc",
        icon_key: "member_management", position: 0, visible: true
      )
      Tempfile.create(%w[snapshot .yml]) do |f|
        f.write(YAML.dump({ "version" => 1, "landing_comparison_tables" => [] }))
        f.flush
        expect do
          described_class.new(path: f.path).call
        end.to raise_error(described_class::Error)
        expect(HomepageFeatureCard.find_by(slug: "member_management")&.title).to eq("Keep Me")
      end
    end
  end

  it "replaces feature cards and comparison tables from the fixture" do
    described_class.new(path: fixture_path).call

    expect(HomepageFeatureCard.count).to eq(1)
    card = HomepageFeatureCard.first
    expect(card.slug).to eq("member_management")
    expect(card.title).to eq("Spec Snapshot Title")
    expect(card.detail_body_present?).to be true

    expect(LandingComparisonTable.count).to eq(3)
    expect(LandingComparisonRow.distinct.pluck(:feature_label)).to eq([ "Spec Compare Row Alpha" ])
  end

  describe "production import guard" do
    it "refuses import without FORCE_LANDING_MARKETING_IMPORT" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      previous_force_landing_marketing_import = ENV["FORCE_LANDING_MARKETING_IMPORT"]
      ENV.delete("FORCE_LANDING_MARKETING_IMPORT")

      begin
        expect do
          described_class.new(path: fixture_path).call
        end.to raise_error(described_class::Error, /FORCE_LANDING_MARKETING_IMPORT/)
      ensure
        if previous_force_landing_marketing_import.nil?
          ENV.delete("FORCE_LANDING_MARKETING_IMPORT")
        else
          ENV["FORCE_LANDING_MARKETING_IMPORT"] = previous_force_landing_marketing_import
        end
      end
    end

    it "allows import when FORCE_LANDING_MARKETING_IMPORT=1" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      ENV["FORCE_LANDING_MARKETING_IMPORT"] = "1"

      begin
        described_class.new(path: fixture_path).call
        expect(HomepageFeatureCard.find_by(slug: "member_management")&.title).to eq("Spec Snapshot Title")
      ensure
        ENV.delete("FORCE_LANDING_MARKETING_IMPORT")
      end
    end
  end
end
