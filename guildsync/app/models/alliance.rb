# frozen_string_literal: true

class Alliance < ApplicationRecord
  has_one_attached :logo

  include ValidatesImageAttachment
  validates_image_attachment :logo

  belongs_to :leader_guild, class_name: "Guild"
  belongs_to :leader_user,  class_name: "User"

  has_many :alliance_guilds,        dependent: :destroy
  has_many :guilds,                 through: :alliance_guilds
  has_many :alliance_members,       dependent: :destroy
  has_many :users,                  through: :alliance_members
  has_many :alliance_invites,       dependent: :destroy
  has_many :alliance_join_requests, dependent: :destroy
  has_many :alliance_disband_votes, dependent: :destroy
  has_many :alliance_events,        dependent: :destroy
  has_many :alliance_polls,         dependent: :destroy
  has_many :alliance_loot_rolls,    dependent: :destroy
  has_many :alliance_messages,      dependent: :destroy
  has_many :alliance_tags,          dependent: :destroy
  has_many :alliance_activity_logs, dependent: :destroy

  enum :status, { active: 0, disbanded: 1 }

  validates :name,           presence: true, length: { minimum: 2, maximum: 60 }
  validates :leader_guild_id, presence: true
  validates :leader_user_id,  presence: true

  scope :active_alliances, -> { where(status: :active) }

  # All GMs (guild owners) currently in this alliance
  def gm_users
    User.where(
      id: Guild.joins(:alliance_guild_memberships)
              .where(alliance_guilds: { alliance_id: id, status: :active })
              .select(:owner_id)
    ).distinct
  end

  def active_guild_ids
    alliance_guilds.where(status: :active).pluck(:guild_id)
  end

  def active_guild_count
    alliance_guilds.where(status: :active).count
  end

  def can_add_more_guilds?
    active_guild_count < 20
  end

  # Disband the alliance: mark disbanded, remove active guild memberships
  def disband!
    transaction do
      update!(status: :disbanded)
      alliance_guilds.where(status: :active).update_all(status: 2)  # left
      alliance_members.where(status: :active).update_all(status: 1) # removed
    end
  end

  # Check if the majority of GMs have voted to disband (> 50%)
  def majority_voted_to_disband?
    total_gm_guilds = alliance_guilds.where(status: :active).count
    disband_votes   = alliance_disband_votes.where(vote: true).count
    return false if total_gm_guilds.zero?
    disband_votes.to_f / total_gm_guilds > 0.5
  end
end
