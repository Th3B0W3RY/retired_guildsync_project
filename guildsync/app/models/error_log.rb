class ErrorLog < ApplicationRecord
  SEVERITIES = %w[low medium high urgent stable].freeze

  validates :error_class, :message, :occurred_at, presence: true
  validates :severity, inclusion: { in: SEVERITIES }

  scope :recent, -> { order(occurred_at: :desc) }
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :with_severity, ->(s) { s.present? ? where(severity: s) : all }

  def resolved?
    resolved_at.present?
  end

  def resolve!(admin_email)
    update!(resolved_at: Time.current, resolved_by: admin_email)
  end
end

