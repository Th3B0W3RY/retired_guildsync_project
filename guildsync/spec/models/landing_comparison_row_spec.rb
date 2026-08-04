# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingComparisonRow, type: :model do
  it "requires unique position per table" do
    table = LandingComparisonTable.find_by!(position: 0)
    create(:landing_comparison_row, landing_comparison_table: table, position: 100, feature_label: "Dup test A")
    dup = build(:landing_comparison_row, landing_comparison_table: table, position: 100, feature_label: "Dup test B")
    expect(dup).not_to be_valid
  end
end
