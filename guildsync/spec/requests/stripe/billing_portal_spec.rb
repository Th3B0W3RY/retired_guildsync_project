require "rails_helper"

RSpec.describe "Billing portal", type: :request do
  let(:original_app_url) { ENV["APP_URL"] }
  let(:original_secret_key) { ENV["STRIPE_SECRET_KEY"] }

  # Create user with existing stripe_customer_id to prevent after_create callback
  # from making real Stripe calls. User callbacks create Stripe customer automatically.
  let(:user) { create(:user, stripe_customer_id: "cus_default") }

  before do
    ENV["STRIPE_SECRET_KEY"] ||= "sk_test_dummy"
    ENV["APP_URL"] = "http://127.0.0.1:5000"
    # Bypass MFA for test user
    user.update!(auth_method: :discord)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    # Stub all Stripe API calls as a safety net
    stub_request(:any, /api\.stripe\.com/).to_return(status: 200, body: '{"id": "fallback"}', headers: { 'Content-Type' => 'application/json' })
    sign_in user
  end

  after do
    ENV["APP_URL"] = original_app_url
    ENV["STRIPE_SECRET_KEY"] = original_secret_key
  end

  describe "POST /billing/portal" do
    it "creates a Stripe customer when missing and returns portal url" do
      # Clear stripe_customer_id to trigger customer creation
      user.update_column(:stripe_customer_id, nil)
      
      customer = double("Stripe::Customer", id: "cus_123")
      session = double("Stripe::BillingPortal::Session", url: "https://portal.test/session")

      allow(Stripe::Customer).to receive(:create).with(email: user.email).and_return(customer)
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(session)

      post "/billing/portal.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["url"]).to eq("https://portal.test/session")
      expect(user.reload.stripe_customer_id).to eq("cus_123")
    end

    it "uses existing customer without creating a new one" do
      user.update!(stripe_customer_id: "cus_existing")
      session = double("Stripe::BillingPortal::Session", url: "https://portal.test/session")
      allow(Stripe::Customer).to receive(:create)
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(session)

      post "/billing/portal.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["url"]).to eq("https://portal.test/session")
      expect(Stripe::Customer).not_to have_received(:create)
    end

    it "returns 500 when customer creation fails" do
      # Clear stripe_customer_id to trigger customer creation
      user.update_column(:stripe_customer_id, nil)
      
      allow(Stripe::Customer).to receive(:create).and_raise(Stripe::StripeError.new("bad"))

      post "/billing/portal.json"

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["error"]).to include("Failed to initialize billing")
    end

    it "returns 500 when portal session creation fails" do
      # User already has stripe_customer_id, so only Session.create will be called
      allow(Stripe::BillingPortal::Session).to receive(:create).and_raise(Stripe::StripeError.new("bad portal"))

      post "/billing/portal.json"

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["error"]).to include("Failed to open billing portal")
    end
  end
end

