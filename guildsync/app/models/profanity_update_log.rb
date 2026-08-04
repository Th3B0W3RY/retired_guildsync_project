# frozen_string_literal: true

class ProfanityUpdateLog < ApplicationRecord
  validates :timestamp, presence: true

  scope :recent, -> { order(created_at: :desc).limit(10) }

  def self.last_successful
    where("error_messages = '[]' OR error_messages IS NULL").order(created_at: :desc).first
  end

  def self.health_status
    last_run = recent.first
    return { status: "unknown" } unless last_run

    errs = last_run.error_messages
    errs = Array(errs) if errs.is_a?(Hash)
    has_errors = errs.present? && errs.any? { |e| e.to_s.present? }
    if has_errors
      { status: "degraded", errors: errs }
    elsif last_run.new_words_added == 0 && last_run.words_removed == 0
      { status: "healthy_stable" }
    else
      { status: "healthy_updated" }
    end
  end
end
