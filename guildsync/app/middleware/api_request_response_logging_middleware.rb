# frozen_string_literal: true

require "json"

# Basic request/response logging for API paths with sensitive field redaction.
class ApiRequestResponseLoggingMiddleware
  MAX_PREVIEW_LENGTH = 1000
  FILTERED = "[FILTERED]"
  SENSITIVE_KEY_FRAGMENTS = %w[
    password
    token
    secret
    authorization
    api_key
    client_secret
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) unless path.start_with?("/api/")

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    request = ActionDispatch::Request.new(env)
    request_body = read_request_body(env)
    status = nil
    headers = {}
    exception = nil

    begin
      status, headers, response = @app.call(env)
      [status, headers, response]
    rescue => e
      exception = e
      status = 500
      raise
    ensure
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0).round(1)
      log_api_request(
        request: request,
        status: status || 500,
        headers: headers || {},
        duration_ms: duration_ms,
        request_body: request_body,
        exception: exception
      )
    end
  end

  private

  def log_api_request(request:, status:, headers:, duration_ms:, request_body:, exception:)
    payload = {
      event: "api.request",
      method: request.request_method,
      path: request.path,
      status: status,
      duration_ms: duration_ms,
      request_id: request.request_id,
      ip: request.remote_ip,
      user_id: current_user_id(request.env),
      query: truncate_preview(redact_value(request.query_parameters)),
      body: truncate_preview(redact_body_preview(request_body, request.content_mime_type&.to_s)),
      response_content_type: headers["Content-Type"],
      response_content_length: headers["Content-Length"],
      authorization: redact_authorization_header(request.get_header("HTTP_AUTHORIZATION"))
    }

    if exception
      payload[:error_class] = exception.class.name
      payload[:error_message] = truncate_preview(exception.message.to_s)
    end

    Rails.logger.info(payload.to_json)
  rescue => e
    Rails.logger.warn("api.request logging failed: #{e.class}: #{e.message}")
  end

  def current_user_id(env)
    return nil unless env["warden"]
    env["warden"].user&.id
  rescue
    nil
  end

  def read_request_body(env)
    io = env["rack.input"]
    return nil unless io

    raw = io.read
    io.rewind
    raw
  rescue
    nil
  end

  def redact_authorization_header(value)
    return nil if value.blank?
    FILTERED
  end

  def redact_body_preview(raw_body, mime_type)
    return nil if raw_body.nil? || raw_body.empty?
    return FILTERED if mime_type.to_s.downcase.include?("multipart/form-data")

    if mime_type.to_s.downcase.include?("json")
      parsed = JSON.parse(raw_body)
      redact_value(parsed)
    else
      truncate_preview(raw_body)
    end
  rescue JSON::ParserError
    truncate_preview(raw_body)
  end

  def redact_value(value, key = nil)
    if value.is_a?(Hash)
      value.each_with_object({}) do |(k, v), acc|
        key_name = k.to_s
        acc[k] = sensitive_key?(key_name) ? FILTERED : redact_value(v, key_name)
      end
    elsif value.is_a?(Array)
      value.map { |item| redact_value(item, key) }
    elsif sensitive_key?(key)
      FILTERED
    else
      value
    end
  end

  def sensitive_key?(key)
    return false if key.blank?
    downcased = key.to_s.downcase
    SENSITIVE_KEY_FRAGMENTS.any? { |fragment| downcased.include?(fragment) }
  end

  def truncate_preview(value)
    return value if value.nil?
    return value if value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)

    serialized = value.is_a?(String) ? value : value.to_json
    serialized.length > MAX_PREVIEW_LENGTH ? "#{serialized[0...MAX_PREVIEW_LENGTH]}...(truncated)" : serialized
  end
end
