# frozen_string_literal: true

class LandingComparisonTable < ApplicationRecord
  MAX_ROWS = 30

  has_many :landing_comparison_rows, -> { order(:position) }, dependent: :destroy, inverse_of: :landing_comparison_table

  validates :position, presence: true, uniqueness: true, inclusion: { in: 0..2 }
  validates :feature_column_label, :guildsync_column_label, :competitor_column_label,
            presence: true, length: { maximum: 255 }
end
