# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/migrate version uniqueness" do
  it "has no duplicate migration version prefixes" do
    dupes = GuildSync::Migrations::DuplicateVersionDetector.duplicate_versions
    expect(dupes).to be_empty, "Duplicate migration versions: #{dupes.join(', ')}"
  end
end
