# frozen_string_literal: true

FactoryBot.define do
  factory :error_batch_report do
    period_start    { 24.hours.ago }
    period_end      { Time.current }
    total_errors    { 0 }
    unique_clusters { 0 }
    report_data     { { "clusters" => [], "summary" => { "total" => 0 }, "period_hours" => 24 } }
    triggered_by    { "scheduled" }

    trait :with_errors do
      total_errors    { 3 }
      unique_clusters { 2 }
      report_data do
        {
          "period_hours" => 24,
          "summary" => {
            "total" => 3,
            "by_severity" => { "medium" => 2, "low" => 1 },
            "by_class" => { "StandardError" => 2, "RuntimeError" => 1 },
            "new_clusters" => 1,
            "increasing_clusters" => 0
          },
          "clusters" => [
            {
              "error_class"    => "StandardError",
              "fingerprint"    => "something went wrong",
              "count"          => 2,
              "sample_message" => "Something went wrong",
              "first_seen_at"  => 23.hours.ago.iso8601,
              "last_seen_at"   => 1.hour.ago.iso8601,
              "error_ids"      => [1, 2],
              "severities"     => { "medium" => 2 },
              "trend"          => "new"
            },
            {
              "error_class"    => "RuntimeError",
              "fingerprint"    => "boom",
              "count"          => 1,
              "sample_message" => "Boom",
              "first_seen_at"  => 2.hours.ago.iso8601,
              "last_seen_at"   => 2.hours.ago.iso8601,
              "error_ids"      => [3],
              "severities"     => { "low" => 1 },
              "trend"          => "stable"
            }
          ]
        }
      end
    end

    trait :delivered do
      delivered_at { 5.minutes.ago }
    end

    trait :admin_triggered do
      triggered_by { "admin:admin@example.com" }
    end
  end
end
