# frozen_string_literal: true

module LandingCompare
  # Public read model for views: same shape for AR-backed tables and i18n fallback.
  TablePresenter = Struct.new(:feature_column_label, :guildsync_column_label, :competitor_column_label,
                              :show_guildsync_badge, :rows, keyword_init: true)
  RowPresenter = Struct.new(:feature_label, :guildsync_included, :competitor_included, keyword_init: true)

  class Repository
    class << self
      def section_title
        raw = SiteSetting.get("landing_compare_section_title")
        raw.to_s.strip.presence || I18n.t("home.landing.compare_title")
      end

      def tables_for_public
        if database_ready?
          from_database
        else
          from_i18n_fallback
        end
      end

      def database_ready?
        return false unless LandingComparisonTable.count == 3

        positions = LandingComparisonTable.order(:position).pluck(:position)
        return false unless positions == [ 0, 1, 2 ]

        LandingComparisonTable.includes(:landing_comparison_rows).all? do |t|
          t.landing_comparison_rows.exists?
        end
      end

      private

      def from_database
        LandingComparisonTable.order(:position).includes(:landing_comparison_rows).map do |t|
          TablePresenter.new(
            feature_column_label: t.feature_column_label,
            guildsync_column_label: t.guildsync_column_label,
            competitor_column_label: t.competitor_column_label,
            show_guildsync_badge: t.show_guildsync_badge,
            rows: t.landing_comparison_rows.map do |r|
              RowPresenter.new(
                feature_label: r.feature_label,
                guildsync_included: r.guildsync_included,
                competitor_included: r.competitor_included
              )
            end
          )
        end
      end

      def from_i18n_fallback
        feature_header = I18n.t("home.landing.compare.feature")
        gs = I18n.t("app_name")

        [
          fallback_table(feature_header, gs, I18n.t("home.landing.compare.competitor_1"),
            ->(key) { Catalog.competitor_included?(0, key) }),
          fallback_table(feature_header, gs, I18n.t("home.landing.compare.competitor_2"),
            ->(key) { Catalog.competitor_included?(1, key) }),
          fallback_table(feature_header, gs, I18n.t("home.landing.compare.competitor_3"),
            ->(key) { Catalog.competitor_included?(2, key) })
        ]
      end

      def fallback_table(feature_header, gs_label, competitor_label, competitor_included_proc)
        rows = Catalog::FEAT_KEYS.map do |key|
          RowPresenter.new(
            feature_label: I18n.t("home.landing.compare.features.#{key}"),
            guildsync_included: true,
            competitor_included: competitor_included_proc.call(key)
          )
        end
        TablePresenter.new(
          feature_column_label: feature_header,
          guildsync_column_label: gs_label,
          competitor_column_label: competitor_label,
          show_guildsync_badge: true,
          rows: rows
        )
      end
    end
  end
end
