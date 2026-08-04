# frozen_string_literal: true

# Inserts the marketing homepage card `custom_role_system` (if missing) and reapplies
# LandingCompare::Catalog rows so every GuildSync vs … table gains “Custom Role System”
# (GuildSync checked, competitors unchecked per catalog defaults).
class AddCustomRoleSystemHomepageCardAndRefreshCompareTables < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:homepage_feature_cards)

    unless HomepageFeatureCard.exists?(slug: "custom_role_system")
      max_pos = HomepageFeatureCard.maximum(:position)
      HomepageFeatureCard.create!(
        slug: "custom_role_system",
        title: I18n.t("home.landing.features_grid.custom_role_system.title", locale: :en),
        description: I18n.t("home.landing.features_grid.custom_role_system.desc", locale: :en),
        icon_key: "custom_role_system",
        position: max_pos.nil? ? 0 : max_pos + 1,
        visible: true
      )
    end

    return unless table_exists?(:landing_comparison_tables)

    LandingComparisonTable.find_each do |table|
      LandingCompare::Catalog.rebuild_rows_for_table!(table)
    end
  end

  def down
    if table_exists?(:homepage_feature_cards)
      HomepageFeatureCard.find_by(slug: "custom_role_system")&.destroy!
    end
    return unless table_exists?(:landing_comparison_tables)

    LandingComparisonTable.find_each do |table|
      victim = table.landing_comparison_rows.find_by(feature_label: "Custom Role System")
      next unless victim

      victim.destroy!
      table.landing_comparison_rows.order(:position).each_with_index do |row, idx|
        row.update_column(:position, idx)
      end
    end
  end
end
