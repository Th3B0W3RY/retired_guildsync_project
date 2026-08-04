# frozen_string_literal: true

class AllianceDisbandVote < ApplicationRecord
  belongs_to :alliance
  belongs_to :user
  belongs_to :guild

  validates :alliance_id, presence: true
  validates :user_id,     presence: true
  validates :guild_id,    presence: true, uniqueness: { scope: :alliance_id, message: "has already cast a disband vote" }
end
