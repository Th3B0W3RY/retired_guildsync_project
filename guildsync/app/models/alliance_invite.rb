# frozen_string_literal: true

class AllianceInvite < ApplicationRecord
  belongs_to :alliance
  belongs_to :guild
  belongs_to :invited_by_user, class_name: "User"

  enum :status, { pending: 0, accepted: 1, declined: 2 }

  validates :alliance_id,        presence: true
  validates :guild_id,           presence: true
  validates :invited_by_user_id, presence: true

  scope :pending_invites, -> { where(status: :pending) }

  def accept!(accepting_user)
    transaction do
      update!(status: :accepted)

      ag = AllianceGuild.find_or_initialize_by(alliance_id: alliance_id, guild_id: guild_id)
      ag.update!(
        status:             :active,
        joined_at:          Time.current,
        invited_by_user_id: invited_by_user_id
      )

      AllianceMemberSyncService.new(alliance, guild).sync!
    end
  end

  def decline!
    update!(status: :declined)
  end
end
