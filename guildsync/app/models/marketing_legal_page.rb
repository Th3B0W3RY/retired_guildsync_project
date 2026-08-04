# frozen_string_literal: true

class MarketingLegalPage < ApplicationRecord
  KINDS = %w[privacy terms security disaster_recovery].freeze
  TITLES = {
    "privacy" => "Privacy",
    "terms" => "Terms",
    "security" => "Security",
    "disaster_recovery" => "Disaster Recovery and Data Recovery"
  }.freeze
  DEFAULT_BODY_HTML = {
    "privacy" => <<~HTML.squish,
      <div class="trix-content">
        <h2>Overview</h2>
        <p>GuildSync only stores the account, billing, and community-management data required to operate the service. We do not sell customer data, and administrative access to production systems is restricted to authorized operators.</p>
        <h2>What We Store</h2>
        <p>Stored data can include account identifiers, guild configuration, billing metadata, uploaded content, and audit trails required for security and support.</p>
        <h2>Retention</h2>
        <p>We retain data for as long as it is needed to provide the service, comply with legal obligations, and preserve security or billing records. Admins can update this page at any time from the marketing CMS.</p>
      </div>
    HTML
    "terms" => <<~HTML.squish,
      <div class="trix-content">
        <h2>Use of Service</h2>
        <p>GuildSync provides hosted tooling for guild and community operations. You agree to use the service lawfully and not to abuse, disrupt, or attempt to bypass service controls.</p>
        <h2>Accounts and Billing</h2>
        <p>Account owners are responsible for the accuracy of billing information, authorized access to their workspace, and compliance with any plan limits or community rules.</p>
        <h2>Changes</h2>
        <p>GuildSync may update service functionality over time. Material legal or policy changes should be reflected on this page by an authorized administrator before release.</p>
      </div>
    HTML
    "security" => <<~HTML.squish,
      <div class="trix-content">
        <h2>Security Posture</h2>
        <p>GuildSync uses authenticated admin access, database-backed audit logging, and infrastructure controls appropriate for a hosted SaaS application.</p>
        <h2>Operational Controls</h2>
        <p>Backups, monitoring, and error reporting are managed through production infrastructure and admin tooling. Sensitive configuration is stored outside Git and should be rotated through approved operational procedures.</p>
        <h2>Reporting</h2>
        <p>If you discover a potential security issue, contact the GuildSync team through the support channels configured by the administrators.</p>
      </div>
    HTML
    "disaster_recovery" => <<~HTML.squish
      <div class="trix-content">
        <h2>Disaster recovery &amp; data recovery</h2>
        <p>GuildSync is designed for operational resilience: configuration and long-form policies are stored in the production database, and routine infrastructure practices include backups and monitoring appropriate for a hosted SaaS product.</p>
        <h2>Backups &amp; retention</h2>
        <p>Backup frequency, retention windows, and restore procedures are defined by your hosting and database providers. Authorized operators should follow your organization’s runbooks for testing restores and validating recovery objectives.</p>
        <h2>User-generated content</h2>
        <p>Where soft delete is enabled, removed guild content is retained for a period to support auditing and administrative recovery. Administrators can review and restore items from the admin recovery tools when appropriate.</p>
        <h2>Contact</h2>
        <p>For operational or contractual questions about recovery commitments, use the support channels configured for your workspace.</p>
      </div>
    HTML
  }.freeze

  has_rich_text :body

  validates :kind, presence: true, uniqueness: true, inclusion: { in: KINDS }
  validates :title, :body, presence: true

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_kind
  before_validation :assign_default_position, on: :create
  before_validation :assign_default_title

  def self.ensure_defaults!
    KINDS.each_with_index do |kind, position|
      page = find_or_initialize_by(kind: kind)
      page.title = TITLES.fetch(kind) if page.title.blank?
      page.position = position if page.new_record? || page.position.nil?
      page.body = DEFAULT_BODY_HTML.fetch(kind) if page.body.blank?
      page.save! if page.new_record? || page.changed? || page.body.body.blank?
    end
  end

  def self.for_kind!(kind)
    ensure_defaults!
    find_by!(kind: kind.to_s.downcase)
  end

  def to_param
    kind
  end

  private

  def normalize_kind
    self.kind = kind.to_s.downcase.strip
  end

  def assign_default_position
    self.position = KINDS.index(kind) || (self.class.maximum(:position) || -1) + 1 if position.nil?
  end

  def assign_default_title
    self.title = TITLES[kind] if title.blank? && kind.present?
  end
end
