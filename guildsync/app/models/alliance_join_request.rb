# frozen_string_literal: true

class AllianceJoinRequest < ApplicationRecord
  belongs_to :alliance
  belongs_to :requesting_guild, class_name: "Guild"
  belongs_to :requested_by_user, class_name: "User"

  enum :status, { pending: 0, accepted: 1, declined: 2 }

  validates :alliance_id, presence: true
  validates :requesting_guild_id, presence: true
  validates :requested_by_user_id, presence: true

  validate :alliance_must_be_active
  validate :requesting_guild_not_in_an_alliance
  validate :no_conflicting_pending_invite, on: :create

  scope :pending_requests, -> { where(status: :pending) }

  # Returns true on success. On failure, populates +errors+ and rolls back.
  def accept!(accepting_user)
    return false unless pending?

    Alliance.transaction do
      alliance.reload
      requesting_guild.reload

      unless alliance.active?
        errors.add(:base, I18n.t("alliances.join_requests.errors.alliance_inactive"))
        raise ActiveRecord::Rollback
      end

      if requesting_guild.alliance_guild&.active?
        errors.add(:base, I18n.t("alliances.join_requests.errors.requesting_already_in_alliance"))
        raise ActiveRecord::Rollback
      end

      unless alliance.can_add_more_guilds?
        errors.add(:base, I18n.t("alliances.join_requests.errors.max_guilds"))
        raise ActiveRecord::Rollback
      end

      begin
        ag = AllianceGuild.find_or_initialize_by(alliance_id: alliance_id, guild_id: requesting_guild_id)
        ag.update!(
          status:               :active,
          joined_at:            Time.current,
          invited_by_user_id:   accepting_user.id
        )

        AllianceMemberSyncService.new(alliance, requesting_guild).sync!

        update!(status: :accepted)
      rescue ActiveRecord::RecordInvalid => e
        msg = e.record&.errors&.full_messages&.join(", ").presence || e.message
        errors.add(:base, msg)
        raise ActiveRecord::Rollback
      rescue StandardError => e
        Rails.logger.error "[AllianceJoinRequest#accept!] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        errors.add(:base, I18n.t("alliances.join_requests.errors.accept_failed"))
        raise ActiveRecord::Rollback
      end
    end

    errors.empty?
  end

  def decline!
    update!(status: :declined)
  end

  private

  def alliance_must_be_active
    return if alliance.blank?

    errors.add(:alliance, I18n.t("alliances.join_requests.errors.alliance_inactive")) unless alliance.active?
  end

  def requesting_guild_not_in_an_alliance
    return if requesting_guild.blank?

    if requesting_guild.alliance_guild&.active?
      errors.add(:requesting_guild, I18n.t("alliances.join_requests.errors.already_in_alliance"))
    end
  end

  def no_conflicting_pending_invite
    return if alliance.blank? || requesting_guild.blank?

    if AllianceInvite.exists?(alliance_id: alliance_id, guild_id: requesting_guild_id, status: :pending)
      errors.add(:base, I18n.t("alliances.join_requests.errors.pending_invite"))
    end
  end
end
