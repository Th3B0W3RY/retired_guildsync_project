# frozen_string_literal: true

class SeedHomepageFeatureCardsFromI18n < ActiveRecord::Migration[8.0]
  SLUGS = %w[
    member_management analytics_insights automation_tools advanced_tracking
    multi_guild custom_automation analytics_dashboard role_management
    member_onboarding event_management custom_notifications moderation_tools
    api_integration export_backup priority_support security_features
    custom_branding mobile_app unlimited_storage
  ].freeze

  def up
    return if HomepageFeatureCard.exists?

    SLUGS.each_with_index do |slug, i|
      HomepageFeatureCard.create!(
        slug: slug,
        title: I18n.t("home.landing.features_grid.#{slug}.title", locale: :en),
        description: I18n.t("home.landing.features_grid.#{slug}.desc", locale: :en),
        icon_key: slug,
        position: i,
        visible: true
      )
    end
  end

  def down
    # Destroy rows so ActionText `rich_texts` are removed (delete_all would orphan them).
    HomepageFeatureCard.where(slug: SLUGS).find_each(&:destroy!)
  end
end
