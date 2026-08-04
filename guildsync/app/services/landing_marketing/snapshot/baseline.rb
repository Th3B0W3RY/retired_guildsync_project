# frozen_string_literal: true

module LandingMarketing
  module Snapshot
    # Builds the canonical in-repo snapshot hash from English i18n (feature cards) and
    # LandingCompare::Catalog (comparison rows). Used to regenerate
    # config/landing/marketing_snapshot.yml without a database.
    module Baseline
      module_function

      def as_hash
        {
          "version" => 1,
          "homepage_feature_cards" => homepage_feature_cards_payload,
          "landing_comparison_tables" => landing_comparison_tables_payload
        }
      end

      def to_yaml
        YAML.dump(as_hash)
      end

      def homepage_feature_cards_payload
        HomepageFeatureCard::ICON_KEYS.each_with_index.map do |slug, i|
          {
            "slug" => slug,
            "title" => I18n.t("home.landing.features_grid.#{slug}.title", locale: :en),
            "description" => I18n.t("home.landing.features_grid.#{slug}.desc", locale: :en),
            "icon_key" => slug,
            "position" => i,
            "visible" => true,
            "body_html" => ""
          }
        end
      end

      def landing_comparison_tables_payload
        competitors = [
          "Guild Manager",
          "GuildSpire",
          "Typical Guild Manager Solutions"
        ]
        (0..2).map do |pos|
          {
            "position" => pos,
            "feature_column_label" => "Feature",
            "guildsync_column_label" => "GuildSync",
            "competitor_column_label" => competitors[pos],
            "show_guildsync_badge" => true,
            "rows" => LandingCompare::Catalog::ROWS.each_with_index.map do |row, idx|
              {
                "position" => idx,
                "feature_label" => row[:label],
                "guildsync_included" => true,
                "competitor_included" => LandingCompare::Catalog.competitor_included?(pos, row[:key])
              }
            end
          }
        end
      end
    end
  end
end
