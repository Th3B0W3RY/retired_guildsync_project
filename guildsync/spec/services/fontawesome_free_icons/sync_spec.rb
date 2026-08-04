# frozen_string_literal: true

require "rails_helper"

RSpec.describe FontawesomeFreeIcons::Sync do
  let(:sample_json) do
    {
      "key" => { "free" => [ "solid" ], "label" => "Key" },
      "star" => { "free" => [ "solid", "regular" ], "label" => "Star" },
      "pro-only" => { "free" => [], "label" => "Pro Only" }
    }.to_json
  end

  it "upserts only free styles from metadata" do
    stub_request(:get, %r{cdn\.jsdelivr\.net/gh/FortAwesome/Font-Awesome@6/metadata/icons\.json})
      .to_return(status: 200, body: sample_json, headers: { "Content-Type" => "application/json" })

    result = described_class.new(metadata_url: "https://cdn.jsdelivr.net/gh/FortAwesome/Font-Awesome@6/metadata/icons.json").call

    expect(result[:icon_definitions]).to eq(3)
    expect(result[:processed]).to eq(3)
    expect(FontawesomeFreeIcon.where(icon_name: "key", style: "solid").count).to eq(1)
    expect(FontawesomeFreeIcon.where(icon_name: "star").pluck(:style)).to contain_exactly("solid", "regular")
    expect(FontawesomeFreeIcon.exists?(icon_name: "pro-only")).to be false
  end

  it "raises on HTTP error" do
    stub_request(:get, %r{cdn\.jsdelivr\.net/gh/FortAwesome/Font-Awesome@6/metadata/icons\.json})
      .to_return(status: 500, body: "no")

    expect do
      described_class.new(metadata_url: "https://cdn.jsdelivr.net/gh/FortAwesome/Font-Awesome@6/metadata/icons.json").call
    end.to raise_error(FontawesomeFreeIcons::Sync::Error, /HTTP 500/)
  end
end
