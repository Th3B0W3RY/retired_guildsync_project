# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingComparisonTable, type: :model do
  it "requires unique position" do
    LandingComparisonTable.find_by!(position: 0)
    dup = build(:landing_comparison_table, position: 0)
    expect(dup).not_to be_valid
    expect(dup.errors[:position]).to be_present
  end

  it "validates position range" do
    expect(build(:landing_comparison_table, position: -1)).not_to be_valid
    expect(build(:landing_comparison_table, position: 3)).not_to be_valid
  end
end
