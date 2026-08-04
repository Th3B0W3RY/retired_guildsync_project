# frozen_string_literal: true

class LandingComparisonRow < ApplicationRecord
  belongs_to :landing_comparison_table, inverse_of: :landing_comparison_rows

  validates :position, presence: true, uniqueness: { scope: :landing_comparison_table_id }
  validates :feature_label, presence: true, length: { maximum: 255 }
end
