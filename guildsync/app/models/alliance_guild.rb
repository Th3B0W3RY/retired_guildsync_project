# frozen_string_literal: true

class AllianceGuild < ApplicationRecord
  belongs_to :alliance
  belongs_to :guild
  belongs_to :invited_by_user, class_name: "User", optional: true

  enum :status, { active: 0, pending_invite: 1, left: 2, kicked: 3 }

  validates :alliance_id, presence: true
  validates :guild_id,    presence: true
  validates :guild_id,    uniqueness: { scope: :alliance_id, message: "is already in this alliance" }
  validate :guild_can_only_have_one_active_alliance, if: :active?

  private

  def guild_can_only_have_one_active_alliance
    return if guild_id.blank?

    existing_active = self.class.where(guild_id: guild_id, status: :active).where.not(id: id)
    return unless existing_active.exists?

    errors.add(:guild_id, "already belongs to an active alliance")
  end
end
