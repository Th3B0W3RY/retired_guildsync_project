# frozen_string_literal: true

require "digest"

class AccountDeletionRequest < ApplicationRecord
  CODE_TTL = 45.minutes
  RESEND_COOLDOWN = SignupEmailVerification::RESEND_COOLDOWN
  MAX_VERIFICATION_ATTEMPTS = 8

  belongs_to :user

  validates :user_id, uniqueness: true

  def self.digest_code(raw)
    Digest::SHA256.hexdigest([ "account_deletion_code", raw.to_s ].join(":"))
  end

  def issue_code!(ip:)
    raw = SecureRandom.hex(4).upcase
    update!(
      code_digest: self.class.digest_code(raw),
      expires_at: CODE_TTL.from_now,
      sent_at: Time.current,
      last_sent_ip: ip,
      attempts_count: 0,
      consumed_at: nil
    )
    raw
  end

  def code_pending?
    consumed_at.nil? && code_digest.present? && expires_at.present? && expires_at.future?
  end

  def resend_available?
    return true if sent_at.blank?

    sent_at <= RESEND_COOLDOWN.ago
  end

  def resend_available_in
    return 0 if resend_available? || sent_at.blank?

    [ (sent_at + RESEND_COOLDOWN - Time.current).ceil, 0 ].max
  end

  # Returns :ok, :invalid, :expired, or :locked
  def verify_submitted_code(raw)
    if attempts_count >= MAX_VERIFICATION_ATTEMPTS
      return :locked
    end

    unless code_pending?
      increment!(:attempts_count)
      return :expired
    end

    candidate = raw.to_s.strip.upcase
    expected = code_digest.to_s
    actual = self.class.digest_code(candidate)
    ok = candidate.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)

    unless ok
      increment!(:attempts_count)
      return :invalid
    end

    update!(consumed_at: Time.current)
    :ok
  end
end
