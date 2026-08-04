class PricingPlan < ApplicationRecord

  # Associations
  has_many :subscriptions, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :price_display, presence: true
  validates :period, presence: true
  validates :display_order, presence: true, numericality: { only_integer: true }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(display_order: :asc, created_at: :asc) }
  scope :popular, -> { where(popular: true) }
  # Paid grid only (excludes the Free tier by name — same as checkout/subscription logic uses `name == "Free"`).
  scope :paid_tiers, -> { where.not("LOWER(TRIM(name)) = ?", "free") }

  # Instance methods
  def free?
    price.nil? || price.zero?
  end

  def free_tier?
    name.to_s.strip.casecmp?("free")
  end

  def unlimited_guilds?
    max_guilds.nil?
  end

  def unlimited_members_per_guild?
    max_members_per_guild.nil?
  end

  def formatted_price
    price_display
  end

  def formatted_period
    return "" if period == "forever" || period == "pricing"
    "/ #{period}"
  end

  # Find plan by Stripe price ID (monthly or annual) in DB.
  def self.find_by_stripe_price(price_id)
    return nil if price_id.blank?
    find_by(stripe_price_id: price_id) || find_by(stripe_price_id_annual: price_id)
  end

  # Find plan by price ID including ENV fallback (so checkout works when price IDs come from ENV).
  def self.find_by_effective_stripe_price(price_id)
    return nil if price_id.blank?
    find_by_stripe_price(price_id) || active.find { |p| p.effective_stripe_price_id == price_id || p.effective_stripe_price_id_annual == price_id }
  end

  def price_id_for_interval(interval)
    interval.to_s == "year" ? effective_stripe_price_id_annual : effective_stripe_price_id
  end

  def formatted_price_annual
    effective_price_display_annual.presence || price_display
  end

  # Use DB value or ENV fallback so test/live work without re-seeding (e.g. STRIPE_BASIC_PRICE_ID).
  def effective_stripe_price_id
    id = stripe_price_id.presence
    return nil if id == "price_placeholder"
    return id if id.present?
    env_key = "STRIPE_#{name.upcase.gsub(/\s+/, '_')}_PRICE_ID"
    ENV[env_key].presence
  end

  def effective_stripe_price_id_annual
    id = stripe_price_id_annual.presence
    return id if id.present?
    env_key = "STRIPE_#{name.upcase.gsub(/\s+/, '_')}_PRICE_ID_ANNUAL"
    ENV[env_key].presence
  end

  # Annual display price: DB or compute from monthly (10% off), else fall back to monthly.
  def effective_price_display_annual
    return price_display_annual if price_display_annual.present?
    if price.present? && price.positive?
      annual = (price * 12 * 0.9).round(2)
      return "$#{format('%.2f', annual)}"
    end
    price_display
  end
end
