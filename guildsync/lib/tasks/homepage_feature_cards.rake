# frozen_string_literal: true

# Optional backfill: creates only missing slugs from EN i18n. Does not overwrite existing cards.
# Production CMS content is authoritative in the DB; use this for empty dev/staging DBs, not to “sync prod from i18n”.
namespace :homepage_feature_cards do
  desc "Create missing homepage feature cards from EN i18n (idempotent; does not overwrite existing rows)"
  task ensure_from_i18n: :environment do
    HomepageFeatureCards::EnsureFromI18n.call
    puts "Homepage feature cards: #{HomepageFeatureCard.count} total, #{HomepageFeatureCard.visible.count} visible."
  end
end
