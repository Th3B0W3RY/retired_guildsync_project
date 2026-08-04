# frozen_string_literal: true

# Shared context for stubbing Stripe API requests
# This is automatically included in all tests to prevent WebMock errors
# All Stripe API calls are stubbed to allow code paths to execute without live API calls
RSpec.configure do |config|
  config.before(:each) do
    @stripe_customer_counter ||= 0
    @stripe_subscription_counter ||= 0
    @stripe_session_counter ||= 0

    # Stub Stripe Customer creation
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return do |_request|
        @stripe_customer_counter += 1
        {
          status: 200,
          body: { id: "cus_test#{@stripe_customer_counter}", email: "test@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Stripe Customer retrieval
    stub_request(:get, %r{https://api\.stripe\.com/v1/customers/cus_.*})
      .to_return do |request|
        customer_id = request.uri.path.split("/").last
        {
          status: 200,
          body: { id: customer_id, email: "test@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Stripe Subscription creation
    stub_request(:post, "https://api.stripe.com/v1/subscriptions")
      .to_return do |_request|
        @stripe_subscription_counter += 1
        {
          status: 200,
          body: {
            id: "sub_test#{@stripe_subscription_counter}",
            status: "active",
            current_period_start: Time.current.to_i,
            current_period_end: 1.month.from_now.to_i
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Stripe Subscription retrieval
    stub_request(:get, %r{https://api\.stripe\.com/v1/subscriptions/sub_.*})
      .to_return do |request|
        subscription_id = request.uri.path.split("/").last
        {
          status: 200,
          body: {
            id: subscription_id,
            status: "active",
            current_period_start: Time.current.to_i,
            current_period_end: 1.month.from_now.to_i
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Stripe Checkout Session creation
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return do |_request|
        @stripe_session_counter += 1
        {
          status: 200,
          body: {
            id: "cs_test#{@stripe_session_counter}",
            url: "https://checkout.stripe.com/test/session#{@stripe_session_counter}"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Stripe Billing Portal Session creation
    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return do |_request|
        {
          status: 200,
          body: {
            id: "bps_test",
            url: "https://billing.stripe.com/test/portal"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub any other Stripe API calls as a catch-all
    stub_request(:any, %r{https://api\.stripe\.com/.*})
      .to_return do |request|
        {
          status: 200,
          body: { id: "stripe_fallback_#{SecureRandom.hex(4)}" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end
  end
end

