# frozen_string_literal: true

module LandingMarketing
  module Snapshot
    # Serializes current DB rows for HomepageFeatureCard and landing comparison CMS tables
    # to YAML (default path: config/landing/marketing_snapshot.yml).
    class Exporter
      def initialize(path: Paths.default_file)
        @path = path
      end

      def call
        payload = {
          "version" => 1,
          "exported_at" => Time.current.utc.iso8601,
          "homepage_feature_cards" => export_cards,
          "landing_comparison_tables" => export_tables
        }
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, YAML.dump(payload))
        @path
      end

      private

      def export_cards
        HomepageFeatureCard.order(:position, :id).map do |c|
          html =
            if c.body.present?
              c.body.to_s
            else
              ""
            end
          {
            "slug" => c.slug,
            "title" => c.title,
            "description" => c.description,
            "icon_key" => c.icon_key,
            "position" => c.position,
            "visible" => c.visible,
            "body_html" => html
          }
        end
      end

      def export_tables
        LandingComparisonTable.order(:position).map do |t|
          {
            "position" => t.position,
            "feature_column_label" => t.feature_column_label,
            "guildsync_column_label" => t.guildsync_column_label,
            "competitor_column_label" => t.competitor_column_label,
            "show_guildsync_badge" => t.show_guildsync_badge,
            "rows" => t.landing_comparison_rows.order(:position).map do |r|
              {
                "position" => r.position,
                "feature_label" => r.feature_label,
                "guildsync_included" => r.guildsync_included,
                "competitor_included" => r.competitor_included
              }
            end
          }
        end
      end
    end
  end
end
