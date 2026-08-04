# frozen_string_literal: true

class GuildDocumentFolder < ApplicationRecord
  belongs_to :guild
  belongs_to :user
  has_many :guild_documents, foreign_key: "folder_id", dependent: :nullify

  validates :name, presence: true, length: { minimum: 1, maximum: 255 }
  validates :color, presence: true, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  def can_manage?(user)
    return false unless user
    return true if guild.owner_id == user.id
    return true if user.id == self.user_id
    
    member = guild.guild_members.find_by(user: user, status: :active)
    member&.admin? || member&.owner?
  end
end

