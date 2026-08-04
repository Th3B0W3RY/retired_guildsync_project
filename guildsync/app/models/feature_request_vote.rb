# frozen_string_literal: true

class FeatureRequestVote < ApplicationRecord
  belongs_to :user
  belongs_to :feature_request

  validates :user_id, uniqueness: { scope: :feature_request_id }
end
