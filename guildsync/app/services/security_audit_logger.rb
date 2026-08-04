class SecurityAuditLogger
  SENSITIVE_KEY_PATTERN = /(password|token|secret|authorization|code|credential)/i
  MAX_VALUE_LENGTH = 500

  class << self
    def log(event:, status:, actor: nil, subject: nil, request: nil, metadata: {})
      return unless enabled?

      payload = {
        event: event.to_s,
        status: status.to_s,
        occurred_at: Time.current.utc.iso8601,
        actor: actor_payload(actor),
        subject: subject_payload(subject),
        request: request_payload(request),
        metadata: sanitize_metadata(metadata)
      }

      message = payload.to_json
      Rails.logger.info("[SECURITY_AUDIT] #{message}")

      if defined?(GuildsyncLoggers)
        GuildsyncLoggers.info(GuildsyncLoggers.security_audit, message)
      end
    rescue => e
      Rails.logger.warn("SecurityAuditLogger failed: #{e.class} #{e.message}")
    end

    private

    def enabled?
      return true if Rails.env.production?
      return false if Rails.env.test?

      # Allow opt-in/out only in non-production, non-test environments (e.g. development).
      raw = ENV["SECURITY_AUDIT_ENABLED"]
      if raw.present?
        return truthy?(raw)
      end

      false
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    def actor_payload(actor)
      return { type: "system" } if actor.nil?

      if actor.respond_to?(:id)
        {
          type: actor.class.name,
          id: actor.id,
          email: actor.respond_to?(:email) ? actor.email : nil
        }
      else
        { type: actor.class.name, id: nil, email: nil }
      end
    end

    def subject_payload(subject)
      return nil if subject.nil?

      if subject.respond_to?(:id)
        { type: subject.class.name, id: subject.id }
      else
        { type: subject.class.name, id: nil }
      end
    end

    def request_payload(request)
      return nil if request.nil?

      {
        request_id: request.request_id,
        method: request.request_method,
        path: request.path,
        ip: request.remote_ip,
        user_agent: request.user_agent
      }
    end

    def sanitize_metadata(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), acc|
          key_str = key.to_s
          acc[key_str] = if key_str.match?(SENSITIVE_KEY_PATTERN)
            "[FILTERED]"
          else
            sanitize_metadata(item)
          end
        end
      when Array
        value.map { |item| sanitize_metadata(item) }
      when String
        value.length > MAX_VALUE_LENGTH ? value[0...MAX_VALUE_LENGTH] : value
      else
        value
      end
    end
  end
end
