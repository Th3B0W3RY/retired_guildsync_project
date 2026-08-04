require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  let(:original_webhook_secret) { ENV["STRIPE_WEBHOOK_SECRET"] }
  let(:original_secret_key) { ENV["STRIPE_SECRET_KEY"] }

  let(:user) { create(:user, stripe_customer_id: "cus_123") }
  let!(:pricing_plan) do
    create(:pricing_plan,
      name: "Basic",
      display_order: 1,
      stripe_price_id: "price_123",
      stripe_price_id_annual: "price_123_annual")
  end

  before do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test"
    ENV["STRIPE_SECRET_KEY"] ||= "sk_test_dummy"
  end

  after do
    ENV["STRIPE_WEBHOOK_SECRET"] = original_webhook_secret
    ENV["STRIPE_SECRET_KEY"] = original_secret_key
  end

  def post_event(event_type:, object:, event_id: nil)
    event_id ||= "evt_#{SecureRandom.hex(8)}"
    payload = object.to_json
    headers = { "HTTP_STRIPE_SIGNATURE" => "sig", "Content-Type" => "application/json" }

    mock_object = build_mock_stripe_object(object)

    mock_event = double("Stripe::Event")
    allow(mock_event).to receive(:type).and_return(event_type)
    allow(mock_event).to receive(:id).and_return(event_id)

    mock_data = double("data")
    allow(mock_data).to receive(:object).and_return(mock_object)
    allow(mock_event).to receive(:data).and_return(mock_data)

    allow(mock_event).to receive(:[]).with("type").and_return(event_type)
    allow(mock_event).to receive(:[]).with("data").and_return({ "object" => object })

    allow(Stripe::Webhook).to receive(:construct_event).with(payload, "sig", "whsec_test")
                                                        .and_return(mock_event)

    post "/stripe/webhooks", env: { "rack.input" => StringIO.new(payload) }, headers: headers
  end

  def build_mock_stripe_object(hash)
    mock = double("StripeObject")
    hash.each do |key, value|
      if value.is_a?(Hash)
        nested_mock = build_mock_stripe_object(value)
        allow(mock).to receive(key.to_sym).and_return(nested_mock)
        allow(mock).to receive(key.to_s).and_return(nested_mock)
      elsif value.is_a?(Array)
        mock_array = value.map { |item| item.is_a?(Hash) ? build_mock_stripe_object(item) : item }
        allow(mock).to receive(key.to_sym).and_return(mock_array)
        allow(mock).to receive(key.to_s).and_return(mock_array)
      else
        allow(mock).to receive(key.to_sym).and_return(value)
        allow(mock).to receive(key.to_s).and_return(value)
      end
    end
    if hash.key?("items") && hash["items"].is_a?(Hash) && hash["items"]["data"].is_a?(Array)
      items_mock = double("items")
      data_array = hash["items"]["data"].map { |item| item.is_a?(Hash) ? build_mock_stripe_object(item) : item }
      data_mock = double("data")
      allow(data_mock).to receive(:first).and_return(data_array.first) if data_array.any?
      allow(data_mock).to receive(:[]).with(0).and_return(data_array.first) if data_array.any?
      allow(items_mock).to receive(:data).and_return(data_mock)
      allow(mock).to receive(:items).and_return(items_mock)
    end
    mock
  end

  def subscription_object(overrides = {})
    {
      "id" => "sub_123",
      "customer" => user.stripe_customer_id,
      "status" => "active",
      "current_period_start" => Time.current.to_i,
      "trial_end" => nil,
      "items" => {
        "data" => [
          { "price" => { "id" => "price_123", "lookup_key" => "basic" } }
        ]
      }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "creates or updates subscription on customer.subscription.created" do
    post_event(
      event_type: "customer.subscription.created",
      object: subscription_object("id" => "sub_created_1")
    )

    expect(response).to have_http_status(:ok)
    expect(user.reload.stripe_subscription_id).to eq("sub_created_1")
    expect(user.plan).to eq("basic")
    subscription = user.subscriptions.find_by(stripe_subscription_id: "sub_created_1")
    expect(subscription).to be_present
    expect(subscription.status).to eq("active")
  end

  it "acknowledges subscription.created for a Stripe customer with no GuildSync user and does not mutate known users" do
    # Users get a free-tier Subscription row on create; orphan Stripe customers must not add another.
    expect do
      post_event(
        event_type: "customer.subscription.created",
        object: subscription_object("id" => "sub_orphan_only_in_stripe", "customer" => "cus_not_in_guildsync")
      )
    end.not_to(change { Subscription.where(user_id: user.id).count })

    expect(response).to have_http_status(:ok)
    expect(user.reload.subscriptions.where(stripe_subscription_id: "sub_orphan_only_in_stripe")).to be_none
    expect(user.stripe_subscription_id).to be_nil
  end

  it "syncs subscription on customer.subscription.updated" do
    post_event(
      event_type: "customer.subscription.updated",
      object: subscription_object("id" => "sub_from_updated_event", "status" => "past_due")
    )

    expect(response).to have_http_status(:ok)
    expect(user.reload.stripe_subscription_id).to eq("sub_from_updated_event")
    sub = user.subscriptions.find_by(stripe_subscription_id: "sub_from_updated_event")
    expect(sub).to be_present
    expect(sub.status).to eq("active")
  end

  it "finds pricing plan by annual price_id (find_by_stripe_price)" do
    post_event(
      event_type: "customer.subscription.created",
      object: subscription_object("id" => "sub_456", "items" => { "data" => [
        { "price" => { "id" => "price_123_annual", "lookup_key" => "basic_annual" } }
      ] })
    )

    expect(response).to have_http_status(:ok)
    subscription = user.subscriptions.find_by(stripe_subscription_id: "sub_456")
    expect(subscription).to be_present
    expect(subscription.pricing_plan).to eq(pricing_plan)
  end

  it "sets plan to free on customer.subscription.deleted" do
    user.update!(stripe_subscription_id: "sub_123")
    create(:subscription, user:, pricing_plan:, stripe_subscription_id: "sub_123")

    post_event(
      event_type: "customer.subscription.deleted",
      object: {
        "id" => "sub_123",
        "customer" => user.stripe_customer_id
      }
    )

    expect(response).to have_http_status(:ok)
    expect(user.reload.plan).to eq("free")
    expect(user.stripe_subscription_id).to be_nil
    expect(user.subscriptions.find_by(stripe_subscription_id: "sub_123")&.status).to eq("canceled")
  end

  it "marks subscription active on invoice.payment_succeeded" do
    create(:subscription, user:, pricing_plan:, stripe_subscription_id: "sub_123", status: :canceled)

    post_event(
      event_type: "invoice.payment_succeeded",
      object: {
        "id" => "in_123",
        "customer" => user.stripe_customer_id,
        "subscription" => "sub_123",
        "period_start" => Time.current.to_i,
        "amount_paid" => 1200,
        "created" => Time.current.to_i
      }
    )

    expect(response).to have_http_status(:ok)
    sub = user.subscriptions.find_by(stripe_subscription_id: "sub_123")
    expect(sub.status).to eq("active")
    expect(sub.first_paid_invoice_at).to be_present
  end

  it "does not set first_paid_invoice_at when amount_paid is zero" do
    create(:subscription, user:, pricing_plan:, stripe_subscription_id: "sub_123", status: :active)

    post_event(
      event_type: "invoice.payment_succeeded",
      object: {
        "id" => "in_zero",
        "customer" => user.stripe_customer_id,
        "subscription" => "sub_123",
        "period_start" => Time.current.to_i,
        "amount_paid" => 0,
        "created" => Time.current.to_i
      }
    )

    expect(response).to have_http_status(:ok)
    expect(user.subscriptions.find_by(stripe_subscription_id: "sub_123").first_paid_invoice_at).to be_nil
  end

  it "logs payment failure without canceling subscription on invoice.payment_failed" do
    create(:subscription, user:, pricing_plan:, stripe_subscription_id: "sub_123", status: :active)

    post_event(
      event_type: "invoice.payment_failed",
      object: {
        "id" => "in_456",
        "customer" => user.stripe_customer_id,
        "subscription" => "sub_123"
      }
    )

    expect(response).to have_http_status(:ok)
    expect(user.subscriptions.find_by(stripe_subscription_id: "sub_123").status).to eq("active")
  end

  it "returns 200 without reprocessing duplicate event ids" do
    event_id = "evt_duplicate_test"
    obj = subscription_object("id" => "sub_dedupe")

    expect do
      post_event(event_type: "customer.subscription.created", object: obj, event_id: event_id)
    end.to change(StripeWebhookEvent, :count).by(1)
    expect(response).to have_http_status(:ok)

    post_event(event_type: "customer.subscription.created", object: obj, event_id: event_id)
    expect(response).to have_http_status(:ok)
    expect(StripeWebhookEvent.where(stripe_event_id: event_id).count).to eq(1)
  end

  it "returns 401 when webhook secret is missing" do
    ENV["STRIPE_WEBHOOK_SECRET"] = nil
    payload = {}.to_json
    post "/stripe/webhooks", env: { "rack.input" => StringIO.new(payload) }, headers: { "HTTP_STRIPE_SIGNATURE" => "sig", "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 400 on JSON parse error" do
    allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError.new("bad json"))
    post "/stripe/webhooks", env: { "rack.input" => StringIO.new("{") }, headers: { "HTTP_STRIPE_SIGNATURE" => "sig", "Content-Type" => "application/json" }

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 401 on signature verification error" do
    allow(Stripe::Webhook).to receive(:construct_event).and_raise(Stripe::SignatureVerificationError.new("bad sig", "sig"))
    post "/stripe/webhooks", env: { "rack.input" => StringIO.new("{}") }, headers: { "HTTP_STRIPE_SIGNATURE" => "sig", "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
