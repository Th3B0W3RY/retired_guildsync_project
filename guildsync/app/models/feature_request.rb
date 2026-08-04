# frozen_string_literal: true

class FeatureRequest < ApplicationRecord
  include SoftDeletable

  soft_delete_metadata display: :title, search: %i[title description]

  STATUSES = %w[considering in_progress qa finished].freeze
  POPULAR_VOTE_THRESHOLD = 15
  DISPLAY_COLUMNS = %w[considering popular in_progress qa finished].freeze
  MODERATION_STATUSES = %w[pending approved rejected flagged].freeze

  belongs_to :user
  belongs_to :moderation_reviewed_by, class_name: "User", optional: true
  has_many :feature_request_votes, dependent: :destroy
  has_many :voters, through: :feature_request_votes, source: :user
  has_many :feature_request_comments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { minimum: 50, maximum: 10_000 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :moderation_status, inclusion: { in: MODERATION_STATUSES }, allow_nil: false

  scope :by_status, ->(s) { where(status: s) }
  scope :popular, -> { where("vote_count > ?", POPULAR_VOTE_THRESHOLD) }
  scope :for_list, -> { order(Arel.sql("is_pinned DESC, vote_count DESC, \"order\" ASC, created_at ASC")) }
  scope :approved, -> { where(moderation_status: "approved") }
  scope :pending_review, -> { where(moderation_status: %w[pending flagged]) }
  scope :visible_to_public, -> { approved }

  def voted_by?(user)
    return false unless user
    feature_request_votes.exists?(user_id: user.id)
  end

  def anonymized_requester_name
    return "An*****" unless user&.username.present?
    name = user.username
    return "*****" if name.length < 2
    name[0, 2] + "*****"
  end

  def visible?
    moderation_status == "approved"
  end

  def moderation_triggered_words_list
    return [] if moderation_triggered_words.blank?
    parsed = JSON.parse(moderation_triggered_words)
    Array(parsed).map(&:to_s).map(&:strip).reject(&:blank?)
  rescue JSON::ParserError, TypeError
    moderation_triggered_words.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  before_validation :apply_content_moderation, on: [ :create, :update ]

  private

  def apply_content_moderation
    # Admin approve/hide/… updates moderation fields without editing copy — do not re-run the filter
    # or a clean record would flip back to "approved" while rejecting a pending row.
    return if persisted? && !title_changed? && !description_changed?

    combined = [ title, description ].compact.join(" ")
    result = ContentModeration::FilterService.new(
      combined,
      content_type: "FeatureRequest",
      user: user
    ).process
    severe = RecruitingVisibilityService.matching_severe_terms(title, description)
    profanity_pending = result[:status] == :pending
    if profanity_pending || severe.any?
      self.moderation_status = "pending"
      profanity_words = profanity_pending ? Array(result[:triggered_words]) : []
      self.moderation_triggered_words = (profanity_words + severe).uniq.to_json
      self.moderation_flagged_at = Time.current
    else
      self.moderation_status = "approved"
      self.moderation_triggered_words = nil
      self.moderation_flagged_at = nil
    end
  end
end
