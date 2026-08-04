# frozen_string_literal: true

FactoryBot.define do
  factory :landing_comparison_table do
    position { 0 }
    feature_column_label { "Feature" }
    guildsync_column_label { "GuildSync" }
    competitor_column_label { "Other" }
    show_guildsync_badge { true }
  end

  factory :landing_comparison_row do
    landing_comparison_table
    sequence(:position)
    sequence(:feature_label) { |n| "Feature #{n}" }
    guildsync_included { true }
    competitor_included { false }
  end
end
