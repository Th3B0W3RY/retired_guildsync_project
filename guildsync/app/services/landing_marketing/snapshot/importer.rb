# frozen_string_literal: true

module LandingMarketing
  module Snapshot
    # Replace strategy: deletes all HomepageFeatureCard and LandingComparisonTable/Row records,
    # then recreates them from the snapshot file. Does not touch LandingUserFeedback, SiteSetting,
    # or any other tables. Idempotent in the sense that the same file yields the same end state.
    class Importer
      class Error < StandardError; end

      def initialize(path: Paths.default_file)
        @path = path
      end

      def call
        assert_production_import_allowed!

        raise Error, "Snapshot file missing: #{@path}" unless File.file?(@path)

        data = YAML.safe_load_file(@path)
        raise Error, "Invalid snapshot (expected Hash)" unless data.is_a?(Hash)
        raise Error, "Unsupported snapshot version: #{data['version'].inspect}" unless data["version"].to_i == 1

        validate_snapshot_shape!(data)

        cards = Array(data["homepage_feature_cards"])
        tables = Array(data["landing_comparison_tables"])

        ActiveRecord::Base.transaction do
          replace_feature_cards!(cards)
          replace_comparison_tables!(tables)
        end

        true
      end

      private

      def assert_production_import_allowed!
        return unless Rails.env.production?
        return if ENV["FORCE_LANDING_MARKETING_IMPORT"].to_s == "1"

        raise Error,
              "Refusing destructive YAML import in production without FORCE_LANDING_MARKETING_IMPORT=1 " \
              "(production DB is the source of truth for Homepage & guest marketing)."
      end

      def validate_snapshot_shape!(data)
        unless data.key?("homepage_feature_cards")
          raise Error, "Malformed snapshot: missing required key 'homepage_feature_cards'"
        end
        unless data.key?("landing_comparison_tables")
          raise Error, "Malformed snapshot: missing required key 'landing_comparison_tables'"
        end
        unless Array(data["homepage_feature_cards"]).all? { |e| e.is_a?(Hash) }
          raise Error, "Malformed snapshot: 'homepage_feature_cards' must be an array of objects"
        end
        unless Array(data["landing_comparison_tables"]).all? { |e| e.is_a?(Hash) }
          raise Error, "Malformed snapshot: 'landing_comparison_tables' must be an array of objects"
        end
      end

      def replace_feature_cards!(rows)
        HomepageFeatureCard.destroy_all

        rows.each do |h|
          card = HomepageFeatureCard.new(
            slug: h["slug"].to_s,
            title: h["title"].to_s,
            description: h["description"].to_s,
            icon_key: h["icon_key"].to_s,
            position: h["position"].to_i,
            visible: ActiveModel::Type::Boolean.new.cast(h.fetch("visible", true))
          )
          body_html = h["body_html"].to_s
          card.body = body_html if body_html.strip.present?
          card.save!
        end
      end

      def replace_comparison_tables!(table_rows)
        LandingComparisonRow.delete_all
        LandingComparisonTable.delete_all

        table_rows.each do |t|
          table = LandingComparisonTable.create!(
            position: t["position"].to_i,
            feature_column_label: t["feature_column_label"].to_s,
            guildsync_column_label: t["guildsync_column_label"].to_s,
            competitor_column_label: t["competitor_column_label"].to_s,
            show_guildsync_badge: ActiveModel::Type::Boolean.new.cast(t.fetch("show_guildsync_badge", true))
          )
          Array(t["rows"]).each do |r|
            table.landing_comparison_rows.create!(
              position: r["position"].to_i,
              feature_label: r["feature_label"].to_s,
              guildsync_included: ActiveModel::Type::Boolean.new.cast(r.fetch("guildsync_included", true)),
              competitor_included: ActiveModel::Type::Boolean.new.cast(r.fetch("competitor_included", false))
            )
          end
        end
      end
    end
  end
end
