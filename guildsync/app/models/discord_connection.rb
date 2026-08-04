require "rest-client"

class DiscordConnection < ApplicationRecord
  belongs_to :guild
  belongs_to :user

  encrypts :access_token, :refresh_token, support_unencrypted_data: true

  validates :guild_id, uniqueness: { message: :one_connection_only }
  validates :user_id, presence: true
  validates :discord_user_id, presence: true
  validates :access_token, presence: true

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def still_valid?
    return false if access_token.blank?
    return false if expired?

    begin
      response = RestClient.get(
        "https://discord.com/api/v10/users/@me",
        { "Authorization" => "Bearer #{access_token}" }
      )
      response.code == 200
    rescue RestClient::ExceptionWithResponse => e
      if e.response.code == 401
        Rails.logger.warn "Discord connection invalid for guild #{guild_id} (401 Unauthorized)"
        false
      else
        Rails.logger.error "Error validating Discord connection (non-401): #{e.response.code} - #{e.response.body}"
        true
      end
    rescue RestClient::RequestTimeout, RestClient::ServerBrokeConnection => e
      Rails.logger.warn "Discord API timeout/connection error for guild #{guild_id}: #{e.message}"
      true
    rescue => e
      Rails.logger.error "Unexpected error validating Discord connection: #{e.message}"
      true
    end
  end

  def valid_or_refresh
    return false if access_token.blank?
    
    if expired? && refresh_token.present?
      begin
        refresh_access_token!
        still_valid?
      rescue => e
        Rails.logger.error "Failed to refresh token for guild #{guild_id}: #{e.message}"
        false
      end
    else
      still_valid?
    end
  end

  def refresh_access_token!
    return unless refresh_token.present?

    begin
      DiscordService.new.refresh_user_token(self)
    rescue => e
      Rails.logger.error "Failed to refresh Discord token: #{e.message}"
      raise
    end
  end
end
