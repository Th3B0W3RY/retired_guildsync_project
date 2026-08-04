# frozen_string_literal: true

class GuildMemberWarningStatus < ApplicationRecord
  WARNING_LIMIT = 3

  belongs_to :guild
  belongs_to :user
  belongs_to :warned_by, class_name: "User", optional: true

  enum :state, { no_warnings: 0, warned: 1, banned: 2 }

  validates :guild_id, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :guild_id }
  validates :warning_count, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: WARNING_LIMIT }

  def apply_warning!(reason:, issuer:)
    self.warning_count = [ warning_count.to_i + 1, WARNING_LIMIT ].min
    self.state = warning_count >= WARNING_LIMIT ? :banned : :warned
    self.last_warning_reason = reason.to_s.strip
    self.last_warned_at = Time.current
    self.warned_by = issuer
    save!
  end

  def move_to_state!(target_state, issuer: nil)
    target = target_state.to_s
    raise ArgumentError, "Invalid warning state" unless self.class.states.key?(target)

    self.state = target
    self.warning_count = case target
    when "no_warnings" then 0
    when "warned" then warning_count.to_i.between?(1, WARNING_LIMIT - 1) ? warning_count : 1
    when "banned" then WARNING_LIMIT
    end
    self.warned_by = issuer if issuer
    save!
  end
end
