# frozen_string_literal: true

class OcrDenial < ApplicationRecord
  belongs_to :user

  after_create :notify_admins_if_critical

  private

  def notify_admins_if_critical
    return unless reason == "hard_stop_reached"

    Rails.logger.info "[OCR] Hard stop reached: user_id=#{user_id} email=#{user&.email} usage=#{current_usage} limit=#{limit}"
  end
end
