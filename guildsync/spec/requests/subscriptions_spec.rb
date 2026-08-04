# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "SubscriptionsController", type: :request do
  let(:user) do
    # Skip Free plan subscription creation so we can create specific test subscriptions
    u = create(:user, skip_free_plan_subscription: true)
    u.update!(auth_method: "discord")
    u
  end
  let(:free_plan) { create(:pricing_plan, name: "Free", price: 0) }
  let(:paid_plan) { create(:pricing_plan, name: "Pro Plan", price: 14.99, stripe_price_id: "price_test123") }
  let(:basic_plan) { create(:pricing_plan, name: "Basic Plan", price: 8.99, stripe_price_id: "price_basic123") }
  let(:elite_plan) { create(:pricing_plan, name: "Elite Plan", price: 24.99, stripe_price_id: "price_elite123") }

  before do
    sign_in user
    # Avoid GET dashboard before nested examples' subscriptions exist — same as billing_spec
    # (ensure_free_plan + multiple current rows breaks trial_active? / current_subscription).
  end

  describe "GET /subscribe" do
    context "with Free plan" do
      it "activates free plan and redirects" do
        get subscribe_path, params: { plan_id: free_plan.id }
        expect(response).to redirect_to(upgrade_pricing_path)
        expect(flash[:notice]).to include("Free plan")
        expect(user.reload.current_subscription&.pricing_plan).to eq(free_plan)
      end
    end

    context "with paid plan without stripe_price_id" do
      let(:plan_no_price) { create(:pricing_plan, name: "Pro Plan", price: 14.99, stripe_price_id: nil) }

      it "redirects with alert" do
        get subscribe_path, params: { plan_id: plan_no_price.id }
        expect(response).to redirect_to(pricing_path)
        expect(flash[:alert]).to include("not available")
      end
    end

    context "with paid plan and stripe_price_id" do
      before do
        # Mock Stripe Checkout session creation
        allow(Stripe::Checkout::Session).to receive(:create).and_return(
          double(url: "https://checkout.stripe.com/session/test123", id: "cs_test123")
        )
      end

      it "creates Stripe Checkout session and redirects" do
        get subscribe_path, params: { plan_id: paid_plan.id }
        expect(response).to redirect_to("https://checkout.stripe.com/session/test123")
        expect(Stripe::Checkout::Session).to have_received(:create)
      end

      it "passes correct parameters to Stripe" do
        get subscribe_path, params: { plan_id: paid_plan.id }
        
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(
            mode: "subscription",
            line_items: [{ price: "price_test123", quantity: 1 }],
            metadata: { user_id: user.id, plan_id: paid_plan.id }
          )
        )
      end

      it "includes success and cancel URLs" do
        get subscribe_path, params: { plan_id: paid_plan.id }
        
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(
            success_url: include("session_id={CHECKOUT_SESSION_ID}"),
            cancel_url: pricing_url
          )
        )
      end

      context "when user is in trial on the same basic plan" do
        let!(:basic_plan_for_trial) { create(:pricing_plan, name: "Basic", price: 8.99, stripe_price_id: "price_basic_trial") }
        before do
          allow(Stripe::Checkout::Session).to receive(:create).and_return(
            double(url: "https://checkout.stripe.com/session/trial", id: "cs_trial")
          )
          create(:subscription, user: user, pricing_plan: basic_plan_for_trial, status: :trialing, trial_ends_at: 7.days.from_now)
        end

        it "does not add trial period days when already trialing the same plan" do
          get subscribe_path, params: { plan_id: basic_plan_for_trial.id }

          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(
              subscription_data: satisfy { |h| !h.key?(:trial_period_days) || h[:trial_period_days].nil? }
            )
          )
        end
      end

      context "when user is not in trial (basic plan eligible)" do
        let!(:basic_plan_for_trial) { create(:pricing_plan, name: "Basic", price: 8.99, stripe_price_id: "price_basic_trial2") }
        before do
          allow(Stripe::Checkout::Session).to receive(:create).and_return(
            double(url: "https://checkout.stripe.com/session/trial2", id: "cs_trial2")
          )
        end

        it "adds 14 day trial period for basic plan" do
          get subscribe_path, params: { plan_id: basic_plan_for_trial.id }

          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(
              subscription_data: hash_including(trial_period_days: 14)
            )
          )
        end
      end

      context "when user has existing Stripe customer ID" do
        let!(:existing_subscription) do
          create(:subscription, user: user, pricing_plan: basic_plan, status: :active,
                 stripe_customer_id: "cus_existing123")
        end

        it "uses existing customer ID" do
          get subscribe_path, params: { plan_id: paid_plan.id }
          
          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(customer: "cus_existing123")
          )
        end
      end

      context "when user has no existing Stripe customer ID" do
        it "does not pass customer parameter" do
          get subscribe_path, params: { plan_id: paid_plan.id }
          
          expect(Stripe::Checkout::Session).to have_received(:create) do |params|
            expect(params[:customer]).to be_nil
          end
        end
      end
    end

    context "with Stripe API error" do
      before do
        error = Stripe::InvalidRequestError.new("Invalid price ID", "price")
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(error)
      end

      it "redirects with error message" do
        get subscribe_path, params: { plan_id: paid_plan.id }
        expect(response).to redirect_to(pricing_path)
        expect(flash[:alert]).to include("Payment processing error")
      end
    end

    it "requires authentication" do
      sign_out user
      # Mock Stripe to avoid real API calls
      allow(Stripe::Checkout::Session).to receive(:create).and_return(
        double(url: "https://checkout.stripe.com/session/test123", id: "cs_test123")
      )
      get subscribe_path, params: { plan_id: paid_plan.id }
      expect(response).to be_redirect
    end
  end

  describe "POST /subscribe" do
    before do
      allow(Stripe::Checkout::Session).to receive(:create).and_return(
        double(url: "https://checkout.stripe.com/session/test123", id: "cs_test123")
      )
    end

    it "creates Stripe Checkout session and redirects" do
      post subscribe_path, params: { plan_id: paid_plan.id }
      expect(response).to redirect_to("https://checkout.stripe.com/session/test123")
    end
  end

  describe "GET /subscriptions/success" do
    let(:stripe_session) do
      double(
        id: "cs_test123",
        metadata: double(user_id: user.id.to_s, plan_id: paid_plan.id.to_s),
        payment_status: "paid",
        subscription: "sub_test123",
        customer: "cus_test123"
      )
    end

    let(:stripe_subscription) do
      double(
        id: "sub_test123",
        items: double(data: [double(price: double(id: "price_test123"))]),
        current_period_start: Time.current.to_i,
        trial_end: nil
      )
    end

    before do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)
      allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_subscription)
    end

    context "with valid session" do
      it "creates subscription and redirects" do
        get success_subscriptions_path, params: { session_id: "cs_test123" }
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to include("activated successfully")
      end

      it "creates subscription with correct attributes" do
        get success_subscriptions_path, params: { session_id: "cs_test123" }
        
        subscription = user.reload.subscriptions.last
        expect(subscription.pricing_plan).to eq(paid_plan)
        expect(subscription.stripe_customer_id).to eq("cus_test123")
        expect(subscription.stripe_subscription_id).to eq("sub_test123")
        expect(subscription.status).to eq("active")
      end

      it "cancels other active subscriptions" do
        existing_sub = create(:subscription, user: user, pricing_plan: basic_plan, status: :active)
        
        get success_subscriptions_path, params: { session_id: "cs_test123" }
        
        expect(existing_sub.reload.status).to eq("canceled")
      end
    end

    context "with invalid session_id" do
      it "redirects with error" do
        get success_subscriptions_path, params: { session_id: nil }
        expect(response).to redirect_to(pricing_path)
        expect(flash[:alert]).to include("Invalid session")
      end
    end

    context "with session for different user" do
      let(:other_user) { create(:user) }
      let(:stripe_session) do
        double(
          id: "cs_test123",
          metadata: double(user_id: other_user.id.to_s, plan_id: paid_plan.id.to_s),
          payment_status: "paid"
        )
      end

      it "redirects with error" do
        get success_subscriptions_path, params: { session_id: "cs_test123" }
        expect(response).to redirect_to(pricing_path)
        expect(flash[:alert]).to include("does not match")
      end
    end

    context "with unpaid session" do
      let(:stripe_session) do
        double(
          id: "cs_test123",
          metadata: double(user_id: user.id.to_s, plan_id: paid_plan.id.to_s),
          payment_status: "unpaid"
        )
      end

      it "redirects with error" do
        get success_subscriptions_path, params: { session_id: "cs_test123" }
        expect(response).to redirect_to(pricing_path)
        expect(flash[:alert]).to include("not completed")
      end
    end
  end
end

