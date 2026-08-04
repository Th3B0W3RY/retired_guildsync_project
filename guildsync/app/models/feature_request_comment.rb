# frozen_string_literal: true

class FeatureRequestComment < ApplicationRecord
  include SoftDeletable

  MODERATION_STATUSES = %w[pending approved rejected flagged].freeze

  belongs_to :feature_request, -> { with_deleted }
  belongs_to :user
  belongs_to :moderation_reviewed_by, class_name: "User", optional: true

  validates :body, presence: true, length: { maximum: 5_000 }
  validates :moderation_status, inclusion: { in: MODERATION_STATUSES }, allow_nil: false

  soft_delete_metadata display: :body, search: %i[body]

  scope :visible, -> { active }
  scope :chronological, -> { order(created_at: :asc) }
  scope :approved, -> { where(moderation_status: "approved") }
  scope :pending_review, -> { where(moderation_status: %w[pending flagged]) }
  scope :visible_to_public, -> { visible.approved }

  before_validation :apply_content_moderation, on: [ :create, :update ]

  def anonymized_author_name
    return "[deleted]" if deleted?
    return "An*****" unless user&.username.present?
    name = user.username
    return "*****" if name.length < 2
    name[0, 2] + "*****"
  end

  def can_delete_by?(user)
    return false unless user
    user.id == user_id || ability_admin?(user)
  end

  def visible?
    deleted_at.nil? && moderation_status == "approved"
  end

  def moderation_triggered_words_list
    return [] if moderation_triggered_words.blank?
    parsed = JSON.parse(moderation_triggered_words)
    Array(parsed).map(&:to_s).map(&:strip).reject(&:blank?)
  rescue JSON::ParserError, TypeError
    moderation_triggered_words.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  private

  def ability_admin?(user)
    admin_emails = ENV.fetch("ADMIN_EMAILS", "").split(",").map { |email| email.strip.downcase }.reject(&:blank?)
    user_email = user.email.to_s.strip.downcase
    return true if user_email.present? && admin_emails.include?(user_email)
    admin_ids = ENV.fetch("ADMIN_USER_IDS", "").split(",").map(&:strip).reject(&:blank?).map(&:to_i)
    admin_ids.include?(user.id)
  end

  def apply_content_moderation
    return if body.blank?
    return if persisted? && !body_changed?

    result = ContentModeration::FilterService.new(
      body,
      content_type: "FeatureRequestComment",
      user: user
    ).process
    severe = RecruitingVisibilityService.matching_severe_terms(body)
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
