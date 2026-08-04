# frozen_string_literal: true

# Handles deferred processing for Discord slash commands.
#
# Retry policy:
#   - Transient network / Discord API errors are retried up to 3 times
#     with polynomial backoff.
#   - Non-recoverable lookup failures (record deleted between enqueue
#     and execution) are discarded immediately.
#
# Idempotency:
#   Uses DiscordCommandExecution to guarantee at-most-once processing.
#   If a retry fires after partial success, the duplicate is skipped.
class DiscordCommandJob < ApplicationJob
  queue_as :default

  # Non-recoverable: record was deleted between enqueue and execution
  discard_on ActiveRecord::RecordNotFound
  discard_on ActiveJob::DeserializationError

  # Transient: Discord/network issues worth retrying
  RETRYABLE_ERRORS = [
    RestClient::ServerBrokeConnection,
    RestClient::RequestTimeout,
    RestClient::GatewayTimeout,
    RestClient::ServiceUnavailable,
    RestClient::TooManyRequests,
    SocketError,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT,
    Net::OpenTimeout,
    Net::ReadTimeout
  ].freeze

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
    Rails.logger.error "[DiscordCommandJob] Exhausted retries for #{job.arguments[0]}##{job.arguments[1]}: #{error.class}: #{error.message}"
    token = job.arguments[2]
    mark_execution_failed(token, job.arguments[1])
    send_error_followup_class(token)
  end

  def perform(service_class, method_name, interaction_token, guild_id, user_id, options = {})
    idempotency_key = method_name.to_s

    # Idempotency: skip if this exact command was already completed
    if DiscordCommandExecution.already_processed?(interaction_token, idempotency_key)
      Rails.logger.info "[DiscordCommandJob] Skipping duplicate: #{service_class}##{method_name} for token #{interaction_token[0..8]}..."
      return
    end

    # Claim the execution slot; nil means another process already claimed it
    execution = DiscordCommandExecution.claim!(interaction_token, idempotency_key)
    unless execution
      Rails.logger.info "[DiscordCommandJob] Execution already claimed: #{service_class}##{method_name}"
      return
    end

    guild = Guild.find(guild_id)
    user  = User.find(user_id)
    service_klass = service_class.to_s.safe_constantize
    unless service_klass
      Rails.logger.error "[DiscordCommandJob] Invalid service class: #{service_class}"
      execution.mark_failed!
      return
    end

    unless method_name.to_s.start_with?("process_") && service_klass.public_method_defined?(method_name)
      Rails.logger.error "[DiscordCommandJob] Rejected command method #{service_class}##{method_name}"
      execution.mark_failed!
      return
    end

    service = service_klass.new

    service.instance_variable_set(:@guild, guild)
    service.instance_variable_set(:@user, user)
    service.instance_variable_set(:@interaction_token, interaction_token)
    service.instance_variable_set(:@guild_member, guild.guild_members.find_by(user: user, status: :active))

    service.public_send(method_name, options.with_indifferent_access)

    execution.mark_completed!
  rescue ActiveRecord::RecordNotFound
    execution&.mark_failed!
    raise
  rescue *RETRYABLE_ERRORS
    execution&.mark_failed!
    raise
  rescue => e
    Rails.logger.error "[DiscordCommandJob] Non-retryable error in #{service_class}##{method_name}: #{e.class}: #{e.message}"
    execution&.mark_failed!
    send_error_followup_class(interaction_token) if interaction_token.present?
  end

  private

  def self.mark_execution_failed(token, method_name)
    DiscordCommandExecution
      .where(interaction_token: token, command_key: method_name.to_s, status: "pending")
      .update_all(status: "failed")
  rescue => e
    Rails.logger.error "[DiscordCommandJob] Failed to mark execution failed: #{e.message}"
  end

  def self.send_error_followup_class(token)
    return unless token.present?
    application_id = ENV["DISCORD_CLIENT_ID"]
    bot_token      = ENV["DISCORD_BOT_TOKEN"]
    url = "https://discord.com/api/v10/webhooks/#{application_id}/#{token}"

    RestClient.post(
      url,
      { content: I18n.t("discord.commands.errors.generic"), flags: 64 }.to_json,
      { "Authorization" => "Bot #{bot_token}", "Content-Type" => "application/json" }
    )
  rescue => e
    Rails.logger.error "[DiscordCommandJob] Failed to send error follow-up: #{e.message}"
  end

  def send_error_followup_class(token)
    self.class.send_error_followup_class(token)
  end
end
