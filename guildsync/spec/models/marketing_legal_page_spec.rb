# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarketingLegalPage, type: :model do
  it "validates allowed kinds" do
    page = described_class.new(kind: "cookies", title: "Cookies", position: 9)
    page.body = "<p>Nope</p>"

    expect(page).not_to be_valid
    expect(page.errors[:kind]).to be_present
  end

  it "requires rich text body content" do
    page = described_class.new(kind: "privacy", title: "Privacy", position: 0)

    expect(page).not_to be_valid
    expect(page.errors[:body]).to be_present
  end

  it "ensures default pages exist by kind" do
    expect(described_class.for_kind!("privacy")).to have_attributes(kind: "privacy")
    expect(described_class.for_kind!("terms")).to have_attributes(kind: "terms")
    expect(described_class.for_kind!("security")).to have_attributes(kind: "security")
    expect(described_class.for_kind!("disaster_recovery")).to have_attributes(kind: "disaster_recovery")
  end
end
