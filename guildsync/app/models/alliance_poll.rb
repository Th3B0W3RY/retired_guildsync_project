# frozen_string_literal: true

class AlliancePoll < ApplicationRecord
  include SoftDeletable

  belongs_to :alliance
  belongs_to :creator, class_name: "User"
  has_many   :alliance_poll_votes, dependent: :destroy
  has_many   :alliance_poll_discord_messages, dependent: :delete_all

  soft_delete_metadata display: :title, search: [ :title, :description ]

  set_callback :soft_delete, :before, :purge_discord_messages

  def purge_discord_messages
    DiscordAlliancePollService.delete_all_linked_messages(self)
  rescue StandardError => e
    Rails.logger.warn "[AlliancePoll] purge_discord_messages poll=#{id}: #{e.class}: #{e.message}"
  end

  validates :title,    presence: true, length: { minimum: 1, maximum: 255 }
  validates :deadline, presence: true
  validates :anonymous, inclusion: { in: [ true, false ] }

  scope :open,    -> { where("deadline > ?", Time.current) }
  scope :closed,  -> { where("deadline <= ?", Time.current) }
  scope :ordered, -> { order(created_at: :desc) }

  def open?
    deadline > Time.current
  end

  def closed?
    !open?
  end

  def vote_counts
    {
      yes:   alliance_poll_votes.where(choice: 0).count,
      no:    alliance_poll_votes.where(choice: 1).count,
      maybe: alliance_poll_votes.where(choice: 2).count
    }
  end

  def total_votes
    alliance_poll_votes.count
  end

  def vote_percentages
    total = total_votes
    return { yes: 0, no: 0, maybe: 0 } if total.zero?

    counts = vote_counts
    {
      yes:   (counts[:yes].to_f / total * 100).round(1),
      no:    (counts[:no].to_f / total * 100).round(1),
      maybe: (counts[:maybe].to_f / total * 100).round(1)
    }
  end

  def user_vote(user)
    return nil unless user
    alliance_poll_votes.find_by(user: user)
  end

  def discord_user_vote(discord_user_id)
    alliance_poll_votes.find_by(discord_user_id: discord_user_id)
  end

  def voters_display_names_by_choice
    return { yes: [], no: [], maybe: [] } if anonymous?

    votes = alliance_poll_votes.includes(:user).to_a
    {
      yes:   votes.select(&:yes?).map   { |v| voter_display_name(v) }.sort,
      no:    votes.select(&:no?).map    { |v| voter_display_name(v) }.sort,
      maybe: votes.select(&:maybe?).map { |v| voter_display_name(v) }.sort
    }
  end

  private

  def voter_display_name(vote)
    vote.user ? vote.user.name_for_discord_embed : (vote.discord_username.presence || "Discord User")
  end
end
