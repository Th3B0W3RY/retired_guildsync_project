# frozen_string_literal: true

class UnregisteredInteractionHandler
  attr_reader :discord_user_id, :discord_username

  def initialize(discord_user_id:, discord_username: nil)
    @discord_user_id = discord_user_id.to_s
    @discord_username = discord_username
  end

  def resolve_user
    @resolved_user ||= begin
      connection = UserDiscordConnection.find_by(discord_user_id: @discord_user_id)
      connection&.user
    end
  end

  def registered?
    resolve_user.present?
  end

  # Product decision (2026-04): unregistered users may interact via Discord ID but must not
  # receive bot DMs. Call sites remain for traceability; this method intentionally does nothing.
  def send_onboarding_dm_if_needed(context_type:, context_id:)
    Rails.logger.debug do
      "[UnregisteredInteractionHandler] Skipping onboarding DM (disabled) discord_user=#{@discord_user_id} context=#{context_type}:#{context_id}"
    end
  end

  def find_existing_interaction(scope, parent_key: nil)
    if resolve_user
      scope.find_by(user_id: resolve_user.id) || scope.find_by(discord_user_id: @discord_user_id)
    else
      scope.find_by(discord_user_id: @discord_user_id)
    end
  end

  def assign_identity(record)
    if resolve_user
      record.user = resolve_user
      record.discord_user_id = nil
      record.discord_username = nil
    else
      record.discord_user_id = @discord_user_id
      record.discord_username = @discord_username
    end
    record
  end

  private
end
