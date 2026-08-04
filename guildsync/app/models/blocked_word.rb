# frozen_string_literal: true

class BlockedWord < ApplicationRecord
  CATEGORIES = %w[profanity spam harassment].freeze

  validates :word, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

  scope :active, -> { where(active: true) }

  def self.terms_for_filter
    active.pluck(:word).map(&:to_s).map(&:strip).reject(&:blank?)
  end
end
