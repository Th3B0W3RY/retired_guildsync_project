# frozen_string_literal: true

module HomepageFeatureCards
  # Creates any missing marketing feature cards using EN locale copy under
  # `home.landing.features_grid.<slug>`. Existing rows are never updated so
  # admin edits in production stay intact.
  class EnsureFromI18n
    class << self
      def call
        return unless table_ready?

        missing_slugs = HomepageFeatureCard::ICON_KEYS - HomepageFeatureCard.pluck(:slug)
        return if missing_slugs.empty?

        next_position = next_position_after_existing
        missing_slugs.each do |slug|
          HomepageFeatureCard.create!(
            slug: slug,
            title: I18n.t("home.landing.features_grid.#{slug}.title", locale: :en),
            description: I18n.t("home.landing.features_grid.#{slug}.desc", locale: :en),
            icon_key: slug,
            position: next_position,
            visible: true
          )
          next_position += 1
        end
      end

      private

      def table_ready?
        ActiveRecord::Base.connection.data_source_exists?(:homepage_feature_cards)
      end

      def next_position_after_existing
        max = HomepageFeatureCard.maximum(:position)
        max.nil? ? 0 : max + 1
      end
    end
  end
end
