# frozen_string_literal: true

class HomepageFeatureCard < ApplicationRecord
  include SoftDeletable

  SLUG_REGEX = /\A[a-z][a-z0-9_]*\z/

  ICON_KEYS = %w[
    member_management analytics_insights automation_tools advanced_tracking
    multi_guild custom_automation analytics_dashboard role_management
    member_onboarding event_management custom_notifications moderation_tools
    api_integration export_backup priority_support security_features
    custom_branding mobile_app unlimited_storage custom_role_system
  ].freeze

  has_rich_text :body

  soft_delete_metadata display: :title, search: [ :slug, :title, :description ]

  FA_ICON_REF_PREFIX = "fa:"

  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_REGEX }
  validates :title, :description, :icon_key, presence: true
  validate :icon_key_must_be_legacy_or_synced_fontawesome

  def self.fa_icon_ref?(key)
    key.to_s.start_with?(FA_ICON_REF_PREFIX)
  end

  # Returns [style, icon_name] e.g. %w[solid key] from "fa:solid:key"
  def self.parse_fa_icon_ref(key)
    return [ nil, nil ] unless fa_icon_ref?(key)

    parts = key.to_s.delete_prefix(FA_ICON_REF_PREFIX).split(":", 2)
    return [ nil, nil ] if parts.size != 2

    style, name = parts
    style = style.to_s.downcase
    name = name.to_s
    return [ nil, nil ] if style.blank? || name.blank?
    return [ nil, nil ] unless FontawesomeFreeIcon::STYLES.include?(style)
    return [ nil, nil ] unless name.match?(/\A[a-z0-9-]+\z/)

    [ style, name ]
  end

  def self.build_fa_icon_ref(style, icon_name)
    s = style.to_s.downcase
    n = icon_name.to_s
    raise ArgumentError, "invalid Font Awesome style" unless FontawesomeFreeIcon::STYLES.include?(s)
    raise ArgumentError, "invalid icon name" if n.blank? || n.include?(":")

    "#{FA_ICON_REF_PREFIX}#{s}:#{n}"
  end

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_slug

  def to_param
    slug
  end

  # Empty Trix/Action Text often persists as blank HTML; treat as "no body" for public pages.
  def detail_body_present?
    body.present? && body.to_plain_text.squish.present?
  end

  private

  def normalize_slug
    self.slug = slug.to_s.downcase.strip
  end

  def icon_key_must_be_legacy_or_synced_fontawesome
    return if icon_key.blank?

    if self.class.fa_icon_ref?(icon_key)
      unless FontawesomeFreeIcon.exists_for_fa_ref?(icon_key)
        errors.add(:icon_key, :invalid_fontawesome_icon)
      end
    elsif ICON_KEYS.exclude?(icon_key)
      errors.add(:icon_key, :inclusion)
    end
  end
end
