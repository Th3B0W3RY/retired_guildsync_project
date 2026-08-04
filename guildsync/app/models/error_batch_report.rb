# frozen_string_literal: true

# Stores the output of each ErrorBatchReportJob run.
# report_data JSON shape:
#   {
#     period_hours: Integer,
#     summary: { total:, by_severity:, by_class:, new_clusters:, increasing_clusters: },
#     clusters: [ { error_class:, fingerprint:, count:, sample_message:,
#                   first_seen_at:, last_seen_at:, error_ids:, severities:, trend: }, ... ]
#   }
class ErrorBatchReport < ApplicationRecord
  validates :period_start, :period_end, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def delivered?
    delivered_at.present?
  end

  def duration_hours
    ((period_end - period_start) / 1.hour).round(1)
  end

  def clusters
    Array(report_data.dig("clusters") || report_data.dig(:clusters))
  end

  def summary
    report_data.dig("summary") || report_data.dig(:summary) || {}
  end
end
