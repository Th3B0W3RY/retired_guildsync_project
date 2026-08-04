# frozen_string_literal: true

class FontawesomeFreeIcon < ApplicationRecord
  STYLES = %w[solid regular brands].freeze

  validates :style, presence: true, inclusion: { in: STYLES }
  validates :icon_name, presence: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :label, presence: true
  validates :icon_name, uniqueness: { scope: :style }

  scope :ordered, -> { order(:style, :icon_name) }

  def self.exists_for_fa_ref?(ref)
    style, name = HomepageFeatureCard.parse_fa_icon_ref(ref)
    return false if style.blank? || name.blank?

    exists?(style: style, icon_name: name)
  end

  def css_classes
    prefix = case style
             when "solid" then "fa-solid"
             when "regular" then "fa-regular"
             when "brands" then "fa-brands"
             end
    "#{prefix} fa-#{icon_name}"
  end

  def to_fa_ref
    HomepageFeatureCard.build_fa_icon_ref(style, icon_name)
  end
end
