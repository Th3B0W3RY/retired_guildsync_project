# frozen_string_literal: true

class GuildInviteLink < ApplicationRecord
  belongs_to :guild
  belongs_to :created_by, class_name: "User"

  before_validation :generate_token, on: :create
  validates :token, presence: true, uniqueness: true

  def self.find_by_token(token)
    find_by(token: token.to_s.presence)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def usable?
    !expired?
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end
