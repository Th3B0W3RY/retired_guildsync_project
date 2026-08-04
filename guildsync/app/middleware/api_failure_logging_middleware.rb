# frozen_string_literal: true

# Logs API request failures to api_failures.txt (path under /api/).
class ApiFailureLoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue => e
    path = env["PATH_INFO"].to_s
    return raise unless path.start_with?("/api/")

    if defined?(GuildsyncLoggers)
      GuildsyncLoggers.log_exception(
        GuildsyncLoggers.api_failures,
        e,
        path: path,
        method: env["REQUEST_METHOD"],
        params_preview: env["action_dispatch.request.request_parameters"]&.to_s&.slice(0, 200)
      )
    end
    raise
  end
end
