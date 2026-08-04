# frozen_string_literal: true

class GuildInvite < ApplicationRecord
  belongs_to :user
  belongs_to :guild
  belongs_to :invited_by, class_name: "User"

  enum :status, {
    pending: 0,
    accepted: 1,
    denied: 2
  }

  scope :not_dismissed, -> { where(dismissed: false) }

  # Only validate uniqueness for pending invites (allow re-invites after accept/deny)
  validate :no_duplicate_pending_invites
  validate :user_not_already_member

  private

  def no_duplicate_pending_invites
    # Only check for duplicates if this is a pending invite
    if status == 'pending' && guild_id.present? && user_id.present?
      existing = GuildInvite.where(guild_id: guild_id, user_id: user_id, status: :pending)
      existing = existing.where.not(id: id) if persisted?
      if existing.exists?
        errors.add(:user_id, :already_invited)
      end
    end
  end

  def user_not_already_member
    # Only validate if this is a new record or status is changing to pending
    # Allow re-invites if user was previously a member (they may have been kicked or left)
    # Only prevent invite if user is currently an ACTIVE member
    if (new_record? || (status_changed? && status == 'pending'))
      member = guild&.guild_members&.find_by(user_id: user_id)
      if member&.active?
        errors.add(:user_id, :already_member)
      end
      # Allow invite if member is inactive/banned or doesn't exist (was kicked/left)
    end
  end
end

