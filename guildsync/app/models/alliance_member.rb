# frozen_string_literal: true

class AllianceMember < ApplicationRecord
  belongs_to :alliance
  belongs_to :user
  belongs_to :guild
  has_many :alliance_member_tags, dependent: :destroy
  has_many :alliance_tags, through: :alliance_member_tags

  enum :role,   { member: 0, officer: 1, gm: 2 }
  enum :status, { active: 0, removed: 1 }

  validates :alliance_id, presence: true
  validates :user_id,     presence: true
  validates :guild_id,    presence: true
  validates :user_id,     uniqueness: { scope: :alliance_id, message: "is already an alliance member" }
  validate :at_most_one_active_alliance_per_user, if: -> { active? }

  scope :active_members, -> { where(status: :active) }

  private

  def at_most_one_active_alliance_per_user
    return if user_id.blank? || alliance_id.blank?

    conflict = AllianceMember.where(user_id: user_id, status: :active).where.not(id: id).where.not(alliance_id: alliance_id).exists?
    return unless conflict

    errors.add(:base, I18n.t("alliances.errors.conflicting_alliance_membership"))
  end

  public

  def role_label
    case role
    when "gm"      then "GM"
    when "officer" then "Officer"
    else                "Member"
    end
  end
end
