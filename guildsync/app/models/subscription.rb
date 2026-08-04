class Subscription < ApplicationRecord
  REFUND_POLICY_WINDOW = 3.days

  # Associations
  belongs_to :user
  belongs_to :pricing_plan

  # Enums
  enum :status, {
    active: 0,
    canceled: 1,
    expired: 2,
    trialing: 3
  }

  # Validations
  validates :started_at, presence: true
  validate :expires_at_after_started_at, if: -> { expires_at.present? && started_at.present? }

  # Scopes
  scope :current, -> { where(status: [ :active, :trialing ]) }
  scope :active_subscriptions, -> { where(status: :active) }
  scope :expired, -> { where(status: :expired).or(where("expires_at < ? AND expires_at IS NOT NULL", Time.current)) }

  # Instance methods
  def active?
    status == "active" || (status == "trialing" && (trial_ends_at.nil? || trial_ends_at > Time.current))
  end

  def expired?
    return false if expires_at.nil? # Never expires
    expires_at < Time.current || status == "expired"
  end

  def in_trial?
    status == "trialing" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def cancel!
    update!(status: :canceled, canceled_at: Time.current)
  end

  def expire!
    update!(status: :expired)
  end

  def refund_eligible?
    return false if first_paid_invoice_at.blank?

    Time.current <= first_paid_invoice_at + REFUND_POLICY_WINDOW
  end

  private

  def expires_at_after_started_at
    return unless expires_at && started_at
    errors.add(:expires_at, :must_be_after_started) if expires_at <= started_at
  end
end
