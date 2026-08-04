class Poll < ApplicationRecord
  include Searchable
  include SoftDeletable

  belongs_to :guild
  belongs_to :creator, class_name: "User", foreign_key: "creator_id"
  has_many :poll_votes, dependent: :destroy

  soft_delete_metadata display: :title, search: [ :title, :description ]

  validates :title, presence: true, length: { minimum: 1, maximum: 255 }
  validates :deadline, presence: true
  validates :anonymous, inclusion: { in: [ true, false ] }

  scope :open, -> { where("deadline > ?", Time.current) }
  scope :closed, -> { where("deadline <= ?", Time.current) }
  scope :ordered, -> { order(created_at: :desc) }

  def open?
    deadline > Time.current
  end

  def closed?
    deadline <= Time.current
  end

  def vote_counts
    {
      yes: poll_votes.where(choice: :yes).count,
      no: poll_votes.where(choice: :no).count,
      maybe: poll_votes.where(choice: :maybe).count
    }
  end

  def total_votes
    poll_votes.count
  end

  def vote_percentages
    total = total_votes
    return { yes: 0, no: 0, maybe: 0 } if total.zero?

    counts = vote_counts
    {
      yes: (counts[:yes].to_f / total * 100).round(1),
      no: (counts[:no].to_f / total * 100).round(1),
      maybe: (counts[:maybe].to_f / total * 100).round(1)
    }
  end

  def user_vote(user)
    return nil unless user
    poll_votes.find_by(user: user)
  end

  def discord_user_vote(discord_user_id)
    poll_votes.find_by(discord_user_id: discord_user_id)
  end
end
