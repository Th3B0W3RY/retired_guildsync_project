require "rotp"
require "rqrcode"

class User < ApplicationRecord
  encrypts :otp_secret, support_unencrypted_data: true

  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :confirmable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: Devise::JWT::RevocationStrategies::Null

  prepend UserDeviseMailDelivery

  # Associations
  has_many :guild_members, dependent: :destroy
  has_many :guilds, through: :guild_members
  has_many :owned_guilds, class_name: "Guild", foreign_key: "owner_id", dependent: :destroy
  has_many :created_events, class_name: "Event", foreign_key: "created_by_id", dependent: :destroy
  has_many :event_participations, dependent: :destroy
  has_many :participated_events, through: :event_participations, source: :event
  has_many :subscriptions, dependent: :destroy
  has_one :current_subscription, -> { current }, class_name: "Subscription"
  has_many :discord_connections, dependent: :destroy
  has_one :user_discord_connection, dependent: :destroy
  has_many :guild_applications, dependent: :destroy
  has_many :guild_invites, dependent: :destroy
  has_many :gear_snapshots, dependent: :destroy
  has_many :gear_upload_requests_as_requester, class_name: "GearUploadRequest", foreign_key: "requester_id", dependent: :destroy
  has_many :gear_upload_requests_as_target, class_name: "GearUploadRequest", foreign_key: "target_user_id", dependent: :destroy
  has_many :login_histories, dependent: :destroy
  has_many :guild_activity_logs, dependent: :nullify
  has_many :guild_member_warning_statuses, dependent: :destroy
  has_many :issued_guild_member_warning_statuses, class_name: "GuildMemberWarningStatus", foreign_key: "warned_by_id", dependent: :nullify
  has_many :user_recent_activities, dependent: :destroy
  has_many :sent_direct_messages, class_name: "DirectMessage", foreign_key: "sender_id", dependent: :destroy
  has_many :received_direct_messages, class_name: "DirectMessage", foreign_key: "recipient_id", dependent: :destroy
  has_many :ocr_usage_changes, dependent: :destroy
  has_many :ocr_requests, dependent: :destroy
  has_many :ocr_denials, dependent: :destroy
  has_many :feature_requests, dependent: :destroy
  has_many :feature_request_votes, dependent: :destroy
  has_many :feature_request_comments, dependent: :destroy
  has_many :backup_codes, dependent: :destroy
  has_many :backup_code_usage_logs, dependent: :destroy
  has_one :account_deletion_request, dependent: :destroy
  has_many :user_compliance_warnings, dependent: :destroy
  has_many :created_guild_tags, class_name: "GuildTag", foreign_key: "created_by_id", dependent: :nullify
  has_many :created_alliance_tags, class_name: "AllianceTag", foreign_key: "created_by_id", dependent: :nullify

  # Alliance associations
  has_many :alliance_members, dependent: :destroy
  has_many :alliances, through: :alliance_members

  def has_valid_discord_connection?
    user_discord_connection&.access_token.present?
  end

  # Active Storage
  has_one_attached :avatar

  include ValidatesImageAttachment
  validates_image_attachment :avatar

  # Guild ownership helper
  def guild_master?(guild)
    guild.owner == self
  end

  # Virtual attributes for plan selection during registration
  attr_accessor :selected_plan_id
  attr_accessor :trial_selected_at_signup
  attr_accessor :skip_free_plan_subscription  # For tests: skip automatic Free plan subscription creation
  attr_accessor :skip_mfa_verification  # For tests: skip MFA verification step (auto-verify session)
  attr_accessor :provisional_registration

  # In-memory store for skip_mfa_verification flags in test environment
  # (Rails.cache uses :null_store in tests, so we use this instead)
  @skip_mfa_verification_flags = {}
  class << self
    attr_accessor :skip_mfa_verification_flags
  end

  # Enums
  enum :auth_method, { mfa: 0, discord: 1, google: 2, microsoft: 3 }, default: :mfa

  # Scopes
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }

  # When set, soft close (Stripe + subscriptions) finished but guild/content rows remain until hard purge.
  # See AccountDeletion::PurgeService and AccountHardPurgeJob.
  def account_closure_hard_purge_due_at
    return nil unless account_closed_at.present?

    account_closed_at + SoftDeletable::RETENTION_PERIOD
  end

  # Devise: Prevent archived users from signing in
  def active_for_authentication?
    super && !archived? && !pending_registration?
  end

  def inactive_message
    return :pending_registration if pending_registration?

    archived? ? :archived : super
  end

  def pending_registration?
    has_attribute?(:registration_completed_at) &&
      has_attribute?(:signup_email_verified_at) &&
      registration_completed_at.nil? &&
      signup_email_verified_at.present?
  end

  def verified_real_email?
    return false if email.to_s.include?("@discord.guildsync.local")

    !has_attribute?(:signup_email_verified_at) || signup_email_verified_at.present?
  end

  def backup_code_regeneration_available?
    return true unless has_attribute?(:backup_code_regenerated_at)
    return true if backup_code_regenerated_at.blank?

    backup_code_regenerated_at <= 3.months.ago
  end

  def backup_code_regeneration_available_at
    return Time.current if backup_code_regeneration_available?

    backup_code_regenerated_at + 3.months
  end

  def oauth_primary_auth?
    discord? || google? || microsoft?
  end

  def provisional_registration?
    ActiveModel::Type::Boolean.new.cast(provisional_registration)
  end

  # One account per IP: prevent multiple accounts from same network (abuse prevention)
  def one_account_per_signup_ip
    return unless respond_to?(:signup_ip) && signup_ip.present?
    # Local integration tests (Playwright, etc.) share 127.0.0.1/::1; allow multiple signups from localhost
    # in test env or when INTEGRATION_TESTS=1 is explicitly set (local dev only, never set in production).
    return if (Rails.env.test? || ENV["INTEGRATION_TESTS"].present?) && %w[127.0.0.1 ::1].include?(signup_ip.to_s)
    return unless User.where(signup_ip: signup_ip).exists?
    errors.add(:base, I18n.t("errors.attributes.user.one_account_per_ip"))
  end

  # Validations
  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :username, length: { minimum: 3, maximum: 30 }
  validates :username, format: { with: /\A[a-zA-Z0-9_]+\z/, message: :invalid_format }
  validates :discord_user_id, uniqueness: { case_sensitive: false, allow_nil: true }, if: -> { discord_user_id.present? }
  validates :google_uid, uniqueness: { case_sensitive: false, allow_nil: true }, if: -> { google_uid.present? }
  validates :microsoft_uid, uniqueness: { case_sensitive: false, allow_nil: true }, if: -> { microsoft_uid.present? }
  validates :preferred_locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true
  validate :password_strength_requirements, if: :password_present_for_strength_validation?
  validate :one_account_per_signup_ip, on: :create

  # Callbacks
  before_validation :set_default_registration_completion, on: :create
  after_create :generate_otp_secret_if_needed
  after_create :ensure_free_plan_subscription, unless: -> { trial_selected_at_signup? || skip_free_plan_subscription? }
  after_create :create_stripe_customer_if_needed
  after_create :set_skip_mfa_verification_flag, if: -> { Rails.env.test? && @skip_mfa_verification_flag == true }

  # Subscription methods
  def current_plan
    # Automatically ensure free plan exists if no subscription is found
    # This handles existing users who were created before the callback was added
    if persisted? && !current_subscription
      ensure_free_plan_subscription
      # Reload the association to get the newly created subscription
      association(:current_subscription).reload
    end
    current_subscription&.pricing_plan
  end

  def current_plan!
    current_plan || raise(ActiveRecord::RecordNotFound, "User has no active subscription")
  end

  def plan_allows?(feature)
    PlanEntitlementService.allowed?(self, feature)
  end

  # Trial methods
  def trial_active?
    # ONLY when status = trialing
    return false unless current_subscription
    current_subscription.status == "trialing" && current_subscription.in_trial?
  end

  def subscribed?
    # ONLY when status = active AND NOT trialing
    return false unless current_subscription
    current_subscription.status == "active" && !current_subscription.in_trial?
  end

  def access_allowed?
    # Allow access if user is subscribed OR is in trial
    subscribed? || trial_active?
  end

  # Paid signup / pricing trials are always this length (matches Stripe subscription_data where applicable).
  STANDARD_TRIAL_PERIOD_DAYS = 14

  # Alliance management (hub for non-members, create/join, strict routes) requires a non-free plan
  # and active app access (active paid subscription OR in-date trial on that paid tier).
  # Free plan stays blocked; expired trial / no subscription blocks via !access_allowed?.
  def blocked_from_alliance_features?
    return true unless current_plan

    current_plan.free? || !access_allowed?
  end

  # Backward-compatible name for join-specific guards (same rule as full alliance access).
  def blocked_from_alliance_join?
    blocked_from_alliance_features?
  end

  def can_create_guild?
    plan = current_plan
    return false unless plan # No subscription = no access
    return true if plan.unlimited_guilds?
    active_owned_guilds_count < plan.max_guilds
  end

  def active_owned_guilds_count(excluding_guild: nil)
    rel = owned_guilds.where(archived_at: nil)
    rel = rel.where.not(id: excluding_guild.id) if excluding_guild
    rel.count
  end

  def can_activate_additional_owned_guild?(excluding_guild: nil)
    plan = current_plan
    return false unless plan
    return true if plan.unlimited_guilds?

    active_owned_guilds_count(excluding_guild: excluding_guild) < plan.max_guilds
  end

  def can_add_member_to_guild?(guild)
    plan = current_plan
    return false unless plan # No subscription = no access
    return true if plan.unlimited_members_per_guild?
    guild.members.count < plan.max_members_per_guild
  end

  def subscribe_to_plan!(pricing_plan, started_at: Time.current, expires_at: nil, trial_ends_at: nil)
    # Cancel only active subscriptions (not expired or trialing)
    # Do NOT cancel expired or trialing ones on new plan selection
    subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)

    # Create new subscription
    subscriptions.create!(
      pricing_plan: pricing_plan,
      status: trial_ends_at ? :trialing : :active,
      started_at: started_at,
      expires_at: expires_at,
      trial_ends_at: trial_ends_at
    )
  end

  # MFA Methods
  def generate_otp_secret_if_needed
    return if otp_secret.present?
    update!(otp_secret: ROTP::Base32.random)
  rescue => e
    Rails.logger.error "Failed to generate OTP secret for user #{id}: #{e.message}"
  end

  def otp_provisioning_uri
    return nil unless otp_secret.present?
    ROTP::TOTP.new(otp_secret, issuer: "GuildSync").provisioning_uri(email)
  end

  def qr_code_svg
    return nil unless otp_provisioning_uri.present?
    qrcode = RQRCode::QRCode.new(otp_provisioning_uri)
    qrcode.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true
    )
  end

  def verify_totp(code)
    return false unless otp_secret.present?
    totp = ROTP::TOTP.new(otp_secret)
    totp.verify(code, drift_behind: 15, drift_ahead: 15)
  end

  def mfa_required?
    # MFA is mandatory - all users must have it enabled and verified
    !mfa_enabled? || !mfa_verified?
  end

  # Create a 14-day trial at signup (NEW USERS ONLY)
  def create_trial_at_signup!(plan)
    raise ArgumentError, "Plan cannot be nil" if plan.nil?
    raise ArgumentError, "Cannot start trial for Free plan" if plan.name == "Free"
    raise ArgumentError, "Only the Basic plan supports a trial" unless plan.name.to_s.strip.casecmp?("basic")
    raise ArgumentError, "User already has a subscription" if subscriptions.current.exists?

    @trial_selected_at_signup = true # Prevent free plan creation

    subscriptions.create!(
      pricing_plan: plan,
      status: :trialing,
      started_at: Time.current,
      trial_ends_at: STANDARD_TRIAL_PERIOD_DAYS.days.from_now
    )
  end

  # Start a 14-day trial for a paid plan (from free plan, if eligible)
  def start_trial_from_free!(plan)
    raise ArgumentError, "Plan cannot be nil" if plan.nil?
    raise ArgumentError, "Cannot start trial for Free plan" if plan.name == "Free"
    raise ArgumentError, "Only the Basic plan supports a trial" unless plan.name.to_s.strip.casecmp?("basic")
    raise ArgumentError, "User has already used a trial" if has_used_trial?
    raise ArgumentError, "User is currently in a trial" if trial_active?

    # Cancel current free plan subscription
    subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)

    subscriptions.create!(
      pricing_plan: plan,
      status: :trialing,
      started_at: Time.current,
      trial_ends_at: STANDARD_TRIAL_PERIOD_DAYS.days.from_now
    )
  end

  # Switch plans during trial (preserves trial_ends_at)
  def switch_plan_during_trial!(new_plan)
    raise ArgumentError, "Plan cannot be nil" if new_plan.nil?
    raise ArgumentError, "Not currently in trial" unless trial_active?
    unless new_plan.name.to_s.strip.casecmp?("basic") || new_plan.name.to_s.strip.casecmp?("free")
      raise ArgumentError, "During a Basic trial, only Basic or Free may be selected without checkout"
    end

    current_sub = current_subscription
    raise ArgumentError, "No active trial subscription found" unless current_sub&.in_trial?

    # Preserve the original trial end date
    trial_ends_at = current_sub.trial_ends_at

    # Cancel current trial subscription
    current_sub.update!(status: :canceled, canceled_at: Time.current)

    # Create new trial subscription with same trial end date
    subscriptions.create!(
      pricing_plan: new_plan,
      status: :trialing,
      started_at: Time.current,
      trial_ends_at: trial_ends_at
    )
  end

  # Downgrade to Free during trial (loses features immediately, keeps trial until end)
  def downgrade_to_free_during_trial!
    raise ArgumentError, "Not currently in trial" unless trial_active?

    free_plan = PricingPlan.find_by!(name: "Free")
    switch_plan_during_trial!(free_plan)
    FreePlanDowngradeSideEffects.call(user: self)
  end


  # Activate Free plan (no trial) - used when trial expires without payment
  def activate_free_plan!
    plan = PricingPlan.find_by!(name: "Free")

    # Cancel any existing active subscriptions
    subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)

    # Cancel any existing trialing subscriptions
    subscriptions.where(status: :trialing).update_all(status: :canceled, canceled_at: Time.current)

    subscriptions.create!(
      pricing_plan: plan,
      status: :active,
      started_at: Time.current
    )
    FreePlanDowngradeSideEffects.call(user: self)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Free plan not found: #{e.message}"
    raise "Free plan must exist. Please run PricingPlanInitializer."
  end

  # Convert expired trial to Free plan (called by ExpireTrialsJob)
  def convert_expired_trial_to_free!
    expired_trial = subscriptions.trialing.where("trial_ends_at < ?", Time.current).first
    return unless expired_trial

    free_plan = PricingPlan.find_by!(name: "Free")
    raise "Free plan must exist" unless free_plan

    # Cancel expired trial
    expired_trial.update!(status: :canceled, canceled_at: Time.current)

    # Cancel any other active subscriptions
    subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)

    # Create Free plan subscription
    subscriptions.create!(
      pricing_plan: free_plan,
      status: :active,
      started_at: Time.current
    )
    FreePlanDowngradeSideEffects.call(user: self)
  end

  # Discord connection helpers
  def has_valid_discord_connection?
    user_discord_connection&.access_token.present?
  end

  def discord_connected?
    has_valid_discord_connection?
  end

  def discord_access_token
    return nil unless user_discord_connection.present?
    user_discord_connection.valid_access_token
  end

  # Display name helper - shows Discord username if available, otherwise username, otherwise cleaned email
  def display_name
    return clean_discord_username(discord_username) if discord_username.present?
    return username if username.present?
    # For Discord emails, extract just the username part before the underscore and ID
    if email&.include?("@discord.guildsync.local")
      email.split("@").first.split("_").first
    else
      email&.split("@").first || "User"
    end
  end

  # For Discord embeds: prefer Discord profile display name, then site username, then Discord login handle.
  def name_for_discord_embed
    discord_global_name.presence ||
      username.presence ||
      clean_discord_username(discord_username).presence ||
      (email&.include?("@discord.guildsync.local") ? email.split("@").first.split("_").first : nil) ||
      email&.split("@").first ||
      "User"
  end

  # Clean Discord username - removes discriminator (#1234) and extra formatting
  def clean_discord_username(username)
    return nil unless username.present?
    # Remove discriminator (everything after #)
    username.split("#").first.strip
  end

  # Discord-facing label for form pre-fill (e.g. guild application) when OAuth-linked.
  # Prefers Discord display name (global_name), then API login username on the connection,
  # then legacy user.discord_username (may include #discriminator). Does not use GuildSync
  # site username. Returns nil when not connected or no usable Discord identity.
  def discord_display_name_for_guild_application
    return nil unless discord_connected?

    gn = discord_global_name.to_s.strip
    return gn if gn.present?

    conn_login = user_discord_connection&.discord_username.to_s.strip
    return conn_login if conn_login.present?

    legacy = discord_username.to_s.strip
    return legacy if legacy.present?

    nil
  end

  # OCR usage (per-plan limits: trial/free = total lifetime, others = monthly)
  OCR_PLAN_LIMITS = {
    "trial" => 3,
    "free" => 3,
    "basic" => 3,
    "upgraded" => 4900,
    "elite" => 9900
  }.freeze

  def ocr_plan
    return nil unless respond_to?(:ocr_billing_plan)
    return ocr_billing_plan.downcase if ocr_billing_plan.present?

    # When ocr_billing_plan is not synced from billing, infer tier from active subscription (matrix plan name).
    tier = current_plan&.name&.to_s&.downcase&.strip
    return tier if tier.present? && OCR_PLAN_LIMITS.key?(tier)

    "free"
  end

  def ocr_monthly_limit
    OCR_PLAN_LIMITS[ocr_plan] || 0
  end

  def ocr_requests_remaining
    return 0 if ocr_locked?
    return Float::INFINITY if respond_to?(:ocr_unlocked) && ocr_unlocked
    limit = ocr_monthly_limit
    used = respond_to?(:ocr_requests_used_this_period) ? ocr_requests_used_this_period : 0
    [ limit - used, 0 ].max
  end

  def ocr_trial?
    ocr_plan == "trial"
  end

  def ocr_free?
    ocr_plan == "free"
  end

  def ocr_upgraded?
    ocr_plan == "upgraded"
  end

  def ocr_elite?
    ocr_plan == "elite"
  end

  def ocr_locked?
    return true if respond_to?(:ocr_hard_locked) && ocr_hard_locked
    return false if respond_to?(:ocr_unlocked) && ocr_unlocked
    # Free plan (expired trial) with 0 limit is effectively locked for OCR
    ocr_free? && ocr_monthly_limit.zero?
  end

  # Used by abuse/usage checks (e.g. banned or suspended)
  def access_restricted?
    return true if respond_to?(:ocr_hard_locked) && ocr_hard_locked
    return true if respond_to?(:locked_at) && locked_at.present?
    false
  end

  def active_ip_conflict_warning
    user_compliance_warnings.active.for_type(UserComplianceWarning::WARNING_TYPE_IP_CONFLICT).order(updated_at: :desc).first
  end

  def ocr_trial_expired?
    return false unless respond_to?(:trial_expired_at)
    trial_expired_at.present? && trial_expired_at < Time.current
  end

  scope :near_ocr_limit, ->(threshold = 0.8) {
    return none unless column_names.include?("ocr_requests_used_this_period") && column_names.include?("ocr_billing_plan")
    where(ocr_billing_plan: [ "trial", "free", "basic", "upgraded", "elite" ]).where(
      "ocr_requests_used_this_period >= CAST((CASE ocr_billing_plan WHEN 'trial' THEN 3 WHEN 'free' THEN 3 WHEN 'basic' THEN 3 WHEN 'upgraded' THEN 4900 WHEN 'elite' THEN 9900 ELSE 0 END) * ? AS INTEGER)",
      threshold
    )
  }

  scope :at_ocr_hard_stop, -> {
    return none unless column_names.include?("ocr_requests_used_this_period") && column_names.include?("ocr_billing_plan")
    where(ocr_billing_plan: "trial").where("ocr_requests_used_this_period >= 3")
      .or(where(ocr_billing_plan: "free").where("ocr_requests_used_this_period >= 3"))
      .or(where(ocr_billing_plan: "basic").where("ocr_requests_used_this_period >= 3"))
      .or(where(ocr_billing_plan: "upgraded").where("ocr_requests_used_this_period >= 4900"))
      .or(where(ocr_billing_plan: "elite").where("ocr_requests_used_this_period >= 9900"))
  }

  # Trial tracking methods
  def has_used_trial?
    # Trial consumed: period ended, or user canceled/forfeited while a trial window was still open
    subscriptions.where.not(trial_ends_at: nil).where("trial_ends_at < ?", Time.current).exists? ||
      subscriptions.where(status: :canceled).where.not(trial_ends_at: nil).where("trial_ends_at > ?", Time.current).exists?
  end

  def can_start_trial?
    # Can start trial if they haven't used one before and aren't currently in trial
    !has_used_trial? && !trial_active?
  end

  # Public method to ensure free plan exists (can be called from controllers)
  def ensure_free_plan_subscription
    return if subscriptions.current.exists?

    free_plan = PricingPlan.find_by(name: "Free")
    return unless free_plan

    subscriptions.create!(
      pricing_plan: free_plan,
      status: :active,
      started_at: Time.current
    )
    Rails.logger.info "Created Free plan subscription for user #{id}"
  rescue => e
    Rails.logger.error "Failed to create Free plan subscription for user #{id}: #{e.message}"
  end

  private

  def trial_selected_at_signup?
    # Check if a trial plan was selected during signup
    # This is set via session or params before user creation
    @trial_selected_at_signup ||= false
  end

  def skip_free_plan_subscription?
    # Check if Free plan subscription creation should be skipped
    # Primarily used in tests to avoid creating unwanted subscriptions
    @skip_free_plan_subscription ||= false
  end

  def create_stripe_customer_if_needed
    # Create Stripe customer on user registration if not already exists
    return if stripe_customer_id.present?
    return unless ENV["STRIPE_SECRET_KEY"].present?

    begin
      customer = Stripe::Customer.create(email: email)
      update_column(:stripe_customer_id, customer.id)
      Rails.logger.info "Created Stripe customer #{customer.id} for user #{id}"
    rescue => e
      Rails.logger.error "Failed to create Stripe customer for user #{id}: #{e.message}"
      # Don't fail user creation if Stripe is unavailable
    end
  end

  def set_skip_mfa_verification_flag
    # Store skip_mfa_verification flag so login flow knows to skip MFA verification
    # In test environment, use in-memory hash (Rails.cache uses :null_store)
    # In other environments, use Rails.cache
    if Rails.env.test?
      self.class.skip_mfa_verification_flags[id] = true
    else
      Rails.cache.write("user_#{id}_skip_mfa_verification", true, expires_in: 5.minutes)
    end
  end

  def self.skip_mfa_verification?(user_id)
    if Rails.env.test?
      skip_mfa_verification_flags[user_id] == true
    else
      Rails.cache.read("user_#{user_id}_skip_mfa_verification") == true
    end
  end

  # Override attribute writer to also set instance variable for callback
  def skip_mfa_verification=(value)
    @skip_mfa_verification_flag = value
    @skip_mfa_verification = value
  end

  def skip_mfa_verification
    @skip_mfa_verification
  end

  def set_default_registration_completion
    return if provisional_registration?
    return unless has_attribute?(:registration_completed_at)
    return if registration_completed_at.present?

    self.registration_completed_at = Time.current
  end

  def password_present_for_strength_validation?
    password.present?
  end

  def password_strength_requirements
    pwd = password.to_s

    unless pwd.match?(/[A-Za-z]/) && pwd.match?(/\d/)
      errors.add(:password, "must include at least one letter and one number")
    end

    if pwd.match?(/\s/)
      errors.add(:password, "cannot contain spaces")
    end

    if username.present? && username.length >= 3 && pwd.downcase.include?(username.downcase)
      errors.add(:password, "cannot contain your username")
    end

    email_local_part = email.to_s.split("@").first.to_s.downcase
    if email_local_part.length >= 3 && pwd.downcase.include?(email_local_part)
      errors.add(:password, "cannot contain your email name")
    end
  end
end
