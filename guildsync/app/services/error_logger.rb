# frozen_string_literal: true

# Central error capture for admin Error Tracker. Use from rescues and background jobs:
#   ErrorLogger.capture(exception)
#   ErrorLogger.capture(exception, context: { user_id: current_user&.id, action: action_name })
class ErrorLogger
  class << self
    # @param exception [Exception, nil] only +Exception+ instances are persisted; +nil+, blank, or other types return +nil+.
    # @param context [Hash] optional context (will be stored as JSON; avoid huge objects)
    # @return [ErrorLog, nil] the created record, or nil if creation failed
    def capture(exception, context: {}, severity: "medium", cause: nil)
      return nil if exception.blank?
      return nil unless exception.is_a?(Exception)

      record = ErrorLog.create!(
        error_class: exception.class.name,
        message: exception.message.to_s.truncate(10_000),
        backtrace: exception.backtrace&.first(200)&.join("\n"),
        context: context.presence,
        occurred_at: Time.current,
        severity: severity.to_s.presence_in(ErrorLog::SEVERITIES) || "medium",
        cause: cause
      )
      if defined?(ErrorDiscordNotifyJob) && SiteSetting.error_immediate_severities.include?(record.severity)
        ErrorDiscordNotifyJob.perform_later(record.id)
      end
      record
    rescue => e
      Rails.logger.error "[ErrorLogger] Failed to persist error: #{e.message}"
      nil
    end
  end
end
