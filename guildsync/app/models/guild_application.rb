class GuildApplication < ApplicationRecord
  belongs_to :user
  belongs_to :guild

  enum :status, { pending: 0, accepted: 1, rejected: 2 }

  validates :discord_username, presence: true
  validates :guild_id, presence: true
  validate :no_duplicate_pending_applications

  private

  def no_duplicate_pending_applications
    # Only prevent duplicate pending applications (allow re-applying after rejection)
    if status == 'pending' && guild_id.present? && user_id.present?
      existing = GuildApplication.where(guild_id: guild_id, user_id: user_id, status: :pending)
      existing = existing.where.not(id: id) if persisted?
      if existing.exists?
        errors.add(:user_id, :already_applied)
      end
    end
  end
end
