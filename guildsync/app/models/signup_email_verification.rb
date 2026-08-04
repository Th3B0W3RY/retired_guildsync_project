# frozen_string_literal: true

require "digest"

class SignupEmailVerification < ApplicationRecord
  TOKEN_TTL = 24.hours
  RESEND_COOLDOWN = 60.seconds

  belongs_to :user, optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, uniqueness: true, allow_nil: true
  validate :profile_email_unique_among_users, if: -> { user_id.present? && email.present? }

  before_validation :normalize_email

  scope :unverified, -> { where(verified_at: nil) }

  def self.normalize_email(value)
    value.to_s.strip.downcase
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_verifiable_token(token)
    verification = find_by(token_digest: digest_token(token))
    return unless verification&.verifiable?

    verification
  end

  def issue!(ip_address:)
    raw_token = SecureRandom.urlsafe_base64(32)
    update!(
      token_digest: self.class.digest_token(raw_token),
      expires_at: TOKEN_TTL.from_now,
      sent_at: Time.current,
      send_count: send_count.to_i + 1,
      last_sent_ip: ip_address
    )
    raw_token
  end

  def verify!
    update!(verified_at: Time.current, token_digest: nil)
  end

  def verifiable?
    verified_at.nil? && token_digest.present? && expires_at.present? && expires_at.future?
  end

  def resend_available?
    return false if verified_at.present?
    return true if sent_at.blank?

    sent_at <= RESEND_COOLDOWN.ago
  end

  def resend_available_in
    return 0 if resend_available? || sent_at.blank?

    [ (sent_at + RESEND_COOLDOWN - Time.current).ceil, 0 ].max
  end

  private

  def normalize_email
    self.email = self.class.normalize_email(email)
  end

  def profile_email_unique_among_users
    return unless User.where.not(id: user_id).exists?(email: email)

    errors.add(:email, :taken)
  end
end
