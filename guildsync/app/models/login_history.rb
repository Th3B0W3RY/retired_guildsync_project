class LoginHistory < ApplicationRecord
  belongs_to :user

  scope :recent, -> { order(login_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :active_sessions, -> { where(logout_at: nil) }

  def active?
    logout_at.nil?
  end

  def self.log_login(user:, ip_address: nil, user_agent: nil)
    create!(
      user: user,
      ip_address: ip_address,
      user_agent: user_agent,
      login_at: Time.current
    )
  end

  def log_logout!
    update!(logout_at: Time.current)
  end
end

