# frozen_string_literal: true

class UserRecentActivity < ApplicationRecord
  MAX_RECENT = 10

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  validates :path, presence: true, length: { maximum: 2048 }
  validates :label, presence: true, length: { maximum: 500 }
  validates :link_path, length: { maximum: 2048 }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }

  after_create :prune_old_activities

  # Only entries that point at a real, revisitable page render as links in the feed.
  # Sign-in/sign-out and other internal actions are recorded without a link_path.
  def linkable?
    link_path.present?
  end

  private

  def prune_old_activities
    ids_to_keep = user.user_recent_activities.recent_first.limit(MAX_RECENT).pluck(:id)
    # `where.not(id: [])` becomes unrestricted SQL (`WHERE 1=1`) and would delete everything.
    return if ids_to_keep.blank?

    user.user_recent_activities.where.not(id: ids_to_keep).delete_all
  end
end
