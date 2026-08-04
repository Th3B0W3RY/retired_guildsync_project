require "rails_helper"

RSpec.describe Rack::Attack do
  describe ".throttled_responder" do
    it "returns X-RateLimit headers for throttled requests" do
      match_data = {
        limit: 5,
        count: 5,
        period: 60,
        epoch_time: 1_700_000_000
      }
      request = instance_double(ActionDispatch::Request, env: { "rack.attack.match_data" => match_data })

      status, headers, _body = described_class.throttled_responder.call(request)

      expect(status).to eq(429)
      expect(headers["Retry-After"]).to eq("60")
      expect(headers["X-RateLimit-Limit"]).to eq("5")
      expect(headers["X-RateLimit-Remaining"]).to eq("0")
      expect(headers["X-RateLimit-Reset"]).to eq((1_700_000_000 + 60).to_s)
    end
  end
end
