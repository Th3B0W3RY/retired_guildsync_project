# frozen_string_literal: true

# Re-applies LandingCompare::Catalog after adding starter_basic_plan_value row.
# Overwrites landing_comparison_rows only; table headers unchanged. Admins can edit again afterward.
class RefreshLandingCompareRowsCatalogPricingRow < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:landing_comparison_tables)

    LandingComparisonTable.order(:position).find_each do |table|
      LandingCompare::Catalog.rebuild_rows_for_table!(table)
    end
  end

  def down
  end
end
