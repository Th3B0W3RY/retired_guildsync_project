require "rails_helper"

RSpec.describe ApiRequestResponseLoggingMiddleware do
  it "logs API requests with redacted sensitive fields" do
    app = lambda do |_env|
      [200, { "Content-Type" => "application/json", "Content-Length" => "12" }, [ "{\"ok\":true}" ]]
    end
    middleware = described_class.new(app)

    env = Rack::MockRequest.env_for(
      "/api/v1/auth/sign_in?api_key=top-secret&sort=created_at",
      method: "POST",
      input: {
        email: "person@example.com",
        password: "plaintext-password",
        access_token: "raw-token"
      }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer super-secret-token"
    )

    expect(Rails.logger).to receive(:info) do |message|
      payload = JSON.parse(message)

      expect(payload["event"]).to eq("api.request")
      expect(payload["path"]).to eq("/api/v1/auth/sign_in")
      expect(payload["status"]).to eq(200)
      expect(payload["authorization"]).to eq("[FILTERED]")

      expect(payload["query"]).to include("\"api_key\":\"[FILTERED]\"")
      expect(payload["query"]).to include("\"sort\":\"created_at\"")

      expect(payload["body"]).to include("\"password\":\"[FILTERED]\"")
      expect(payload["body"]).to include("\"access_token\":\"[FILTERED]\"")
      expect(payload["body"]).to include("\"email\":\"person@example.com\"")
      expect(payload["body"]).not_to include("plaintext-password")
      expect(payload["body"]).not_to include("raw-token")
    end

    middleware.call(env)
  end

  it "does not log non-api routes" do
    app = ->(_env) { [200, { "Content-Type" => "text/html" }, [ "ok" ]] }
    middleware = described_class.new(app)
    env = Rack::MockRequest.env_for("/dashboard")

    expect(Rails.logger).not_to receive(:info).with(include("api.request"))
    middleware.call(env)
  end
end
