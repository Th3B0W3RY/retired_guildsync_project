# frozen_string_literal: true

# Rebuilds comparison row content from LandingCompare::Catalog (new rows, rapid-feedback row,
# competitor columns aligned with marketed capabilities). Preserves table headers and admin settings
# on LandingComparisonTable; replaces only landing_comparison_rows.
class RefreshLandingCompareRowsFromCatalog < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:landing_comparison_tables)

    LandingComparisonTable.order(:position).find_each do |table|
      LandingCompare::Catalog.rebuild_rows_for_table!(table)
    end
  end

  def down
    # Row content is marketing data; restoring prior rows is not supported.
  end
end
