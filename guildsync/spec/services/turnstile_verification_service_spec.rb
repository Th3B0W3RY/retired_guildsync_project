# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe TurnstileVerificationService do
  describe ".enforced?" do
    it "is false when keys are missing" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(nil)
      expect(described_class.enforced?).to be false
    end

    it "is true when both keys are present" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return("site")
      allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return("secret")
      expect(described_class.enforced?).to be true
    end
  end

  describe ".verify" do
    context "when not enforced" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return(nil)
        allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return(nil)
      end

      it "returns :ok without calling Cloudflare" do
        expect(described_class.verify(response_token: nil)).to eq(:ok)
      end
    end

    context "when enforced" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("TURNSTILE_SITE_KEY").and_return("site")
        allow(ENV).to receive(:[]).with("TURNSTILE_SECRET_KEY").and_return("secret")
      end

      it "returns :ok for blank token in test when not strict (Playwright / rails server -e test)" do
        ENV.delete("TURNSTILE_STRICT_IN_TEST")
        expect(described_class.verify(response_token: "")).to eq(:ok)
      end

      it "returns :missing_token when token is blank and TURNSTILE_STRICT_IN_TEST=1" do
        ENV["TURNSTILE_STRICT_IN_TEST"] = "1"
        expect(described_class.verify(response_token: "")).to eq(:missing_token)
      ensure
        ENV.delete("TURNSTILE_STRICT_IN_TEST")
      end

      it "returns :ok when Cloudflare accepts the token" do
        stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
          .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

        expect(described_class.verify(response_token: "valid-token", remote_ip: "203.0.113.1")).to eq(:ok)
      end

      it "returns :invalid when Cloudflare rejects the token" do
        stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
          .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })

        expect(described_class.verify(response_token: "bad")).to eq(:invalid)
      end

      it "returns :error on malformed JSON" do
        stub_request(:post, "https://challenges.cloudflare.com/turnstile/v0/siteverify")
          .to_return(status: 200, body: "not-json", headers: { "Content-Type" => "text/plain" })

        expect(described_class.verify(response_token: "x")).to eq(:error)
      end
    end
  end
end
