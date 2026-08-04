# frozen_string_literal: true

class AllianceActivityLog < ApplicationRecord
  RETENTION_DAYS = 60

  belongs_to :alliance
  belongs_to :user, optional: true
  belongs_to :guild, optional: true

  validates :action_type, presence: true
  validates :description, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_alliance, ->(alliance) { where(alliance_id: alliance.is_a?(Alliance) ? alliance.id : alliance) }
  scope :older_than, ->(time) { where("created_at < ?", time) }
  scope :expired, -> { older_than(RETENTION_DAYS.days.ago) }
end
