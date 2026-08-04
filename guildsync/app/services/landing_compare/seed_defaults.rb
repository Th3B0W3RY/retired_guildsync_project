# frozen_string_literal: true

module LandingCompare
  # Idempotent defaults for landing comparison CMS. Used by migration and test suite
  # (schema:load does not run migration data).
  class SeedDefaults
    class << self
      def seed!
        return unless ActiveRecord::Base.connection.data_source_exists?(:landing_comparison_tables)
        return if fully_seeded?

        LandingComparisonTable.transaction do
          LandingComparisonRow.delete_all
          LandingComparisonTable.delete_all
          insert_tables_and_rows!
        end
      end

      def fully_seeded?
        return false unless LandingComparisonTable.count == 3

        (0..2).all? { |p| LandingComparisonTable.exists?(position: p) } &&
          LandingComparisonTable.order(:position).all.all? { |t| t.landing_comparison_rows.exists? }
      end

      private

      def insert_tables_and_rows!
        t0 = LandingComparisonTable.create!(
          position: 0,
          feature_column_label: "Feature",
          guildsync_column_label: "GuildSync",
          competitor_column_label: "Guild Manager",
          show_guildsync_badge: true
        )
        t1 = LandingComparisonTable.create!(
          position: 1,
          feature_column_label: "Feature",
          guildsync_column_label: "GuildSync",
          competitor_column_label: "GuildSpire",
          show_guildsync_badge: true
        )
        t2 = LandingComparisonTable.create!(
          position: 2,
          feature_column_label: "Feature",
          guildsync_column_label: "GuildSync",
          competitor_column_label: "Typical Guild Manager Solutions",
          show_guildsync_badge: true
        )

        Catalog.rebuild_rows_for_table!(t0)
        Catalog.rebuild_rows_for_table!(t1)
        Catalog.rebuild_rows_for_table!(t2)
      end
    end
  end
end
