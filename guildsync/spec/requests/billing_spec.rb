# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "BillingController", type: :request do
  let(:user) do
    # Skip Free plan subscription creation so we can create specific test subscriptions
    u = create(:user, skip_free_plan_subscription: true)
    # Set auth_method to "discord" to bypass MFA checks in tests
    u.update!(auth_method: "discord")
    u
  end
  let!(:free_plan) { create(:pricing_plan, name: "Free", price: 0) }
  let(:paid_plan) { create(:pricing_plan, name: "Pro", price: 14.99) }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  before do
    sign_in user
    # Do not GET dashboard here: outer before runs before nested `let!(:subscription)` in child
    # examples, which would call `current_plan` / `ensure_free_plan_subscription` and create a Free
    # subscription while the example still expects a single trialing/paid sub — `current_subscription`
    # then resolves to the wrong row and portal/billing assertions fail.
  end

  describe "GET /billing" do
    context "with session_id (checkout success callback)" do
      let(:paid_plan) { create(:pricing_plan, name: "Pro", price: 14.99) }
      let(:session_id) { "cs_success_123" }

      before do
        user.update_column(:stripe_customer_id, "cus_123")
        mock_session = double(
          "Stripe::Checkout::Session",
          payment_status: "paid",
          subscription: "sub_123",
          customer: "cus_123",
          metadata: double(user_id: user.id.to_s, plan_id: paid_plan.id.to_s)
        )
        mock_sub = double(
          "Stripe::Subscription",
          id: "sub_123",
          current_period_start: Time.current.to_i,
          trial_end: nil,
          items: double(data: [double(price: double(id: "price_123"))])
        )
        allow(Stripe::Checkout::Session).to receive(:retrieve).with(session_id).and_return(mock_session)
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_123").and_return(mock_sub)
      end

      it "processes session, persists the subscription, and redirects to dashboard with success notice" do
        expect(user.subscriptions.count).to eq(0)

        get billing_path, params: { session_id: session_id }

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to eq(I18n.t("controllers.billing.checkout_success"))

        sub = user.reload.subscriptions.find_by!(stripe_subscription_id: "sub_123")
        expect(sub).to be_active
        expect(sub.pricing_plan_id).to eq(paid_plan.id)
        expect(sub.stripe_customer_id).to eq("cus_123")
        expect(sub.stripe_price_id).to eq("price_123")
      end

      it "rejects checkout session metadata without user_id" do
        mock_session = double(
          "Stripe::Checkout::Session",
          payment_status: "paid",
          subscription: "sub_999",
          customer: "cus_123",
          metadata: double(user_id: nil, plan_id: paid_plan.id.to_s)
        )
        allow(Stripe::Checkout::Session).to receive(:retrieve).with(session_id).and_return(mock_session)

        get billing_path, params: { session_id: session_id }

        expect(response).to redirect_to(billing_path)
        expect(flash[:alert]).to eq(I18n.t("controllers.billing.invalid_session"))
        expect(user.reload.subscriptions.where(stripe_subscription_id: "sub_999")).not_to exist
      end

      it "rejects checkout session when metadata user_id does not match the signed-in user" do
        mock_session = double(
          "Stripe::Checkout::Session",
          payment_status: "paid",
          subscription: "sub_888",
          customer: "cus_123",
          metadata: double(user_id: (user.id + 999_999).to_s, plan_id: paid_plan.id.to_s)
        )
        allow(Stripe::Checkout::Session).to receive(:retrieve).with(session_id).and_return(mock_session)

        get billing_path, params: { session_id: session_id }

        expect(response).to redirect_to(billing_path)
        expect(flash[:alert]).to eq(I18n.t("controllers.billing.session_mismatch"))
        expect(user.reload.subscriptions.where(stripe_subscription_id: "sub_888")).not_to exist
      end
    end

    context "with active subscription" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :active, started_at: 1.month.ago)
      end

      it "returns success" do
        get billing_path
        expect(response).to have_http_status(:success)
      end

      it "displays subscription information" do
        get billing_path
        expect(response.body).to include(paid_plan.name)
        expect(response.body).to include("Active")
        expect(response.body).to include(paid_plan.formatted_price)
      end

      it "includes support center URL for contact billing team link" do
        get billing_path
        expect(response.body).to include(default_support_url)
      end

      it "includes support center URL on mobile variant" do
        get billing_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://billing-page-support.example/help")
        get billing_path
        expect(response.body).to include("https://billing-page-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://billing-page-support.example/help")
        get billing_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://billing-page-support.example/help")
      end
    end

    context "with trial subscription" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :trialing, 
               trial_ends_at: 7.days.from_now, started_at: 1.week.ago)
      end

      it "displays trial information" do
        get billing_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Trial Period Active")
        expect(response.body).to include("7 days")
      end

      it "calculates trial days remaining correctly" do
        get billing_path
        expect(response.body).to include("7 days")
      end
    end

    context "with free plan subscription" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: free_plan, status: :active, started_at: 1.month.ago)
      end

      it "displays free plan information" do
        get billing_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Free")
      end
    end

    # True "no subscription" is not stable: rendering the app shell / billing can call
    # `current_user.current_plan`, which runs `ensure_free_plan_subscription` and creates Free.
    context "when the user had no subscriptions before visiting billing" do
      before do
        user.subscriptions.destroy_all
        user.reload
      end

      it "creates a Free subscription and shows the current plan" do
        expect(user.subscriptions.count).to eq(0)
        get billing_path
        expect(response).to have_http_status(:success)
        expect(user.reload.subscriptions.count).to eq(1)
        expect(user.current_subscription.pricing_plan.name).to eq("Free")
        expect(response.body).to include("Free")
      end
    end

    it "requires authentication" do
      # Clear session completely
      delete "/sign_out"
      # Clear any remaining session data
      reset_session if respond_to?(:reset_session)
      
      get billing_path
      # Should redirect when not authenticated
      expect(response).to be_redirect
    end

    it "displays setup payment button" do
      create(:subscription, user: user, pricing_plan: paid_plan, status: :trialing, trial_ends_at: 7.days.from_now)
      get billing_path
      expect(response.body).to include("Setup Payment")
    end

    it "displays contact billing team button" do
      get billing_path
      expect(response.body).to include("Contact Our Billing Team")
    end

    it "displays billing portal button" do
      get billing_path
      expect(response.body).to include("Billing Portal")
    end

    it "includes Stimulus pricing-plans markup on setup cards when annual Stripe pricing exists" do
      plan = create(:pricing_plan,
                    name: "BillingAnnualSpec",
                    price: 12,
                    period: "month",
                    price_display: "$12",
                    stripe_price_id: "price_billing_m",
                    stripe_price_id_annual: "price_billing_y",
                    display_order: 95,
                    active: true,
                    max_guilds: 5)
      create(:subscription, user: user, pricing_plan: plan, status: :trialing,
             trial_ends_at: 7.days.from_now, started_at: 1.week.ago)
      get billing_path

      expect(response.body).to include('data-controller="pricing-plans"')
      expect(response.body).to include('data-pricing-plans-target="intervalToggle"')
    end
  end

  describe "POST /billing/portal" do
    context "with Stripe customer ID" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :trialing,
               trial_ends_at: 7.days.from_now, started_at: 1.week.ago,
               stripe_customer_id: "cus_test123")
      end

      before do
        # Mock Stripe Billing Portal session creation
        allow(Stripe::BillingPortal::Session).to receive(:create).and_return(
          double(url: "https://billing.stripe.com/session/test123")
        )
      end

      it "creates billing portal session and redirects" do
        post billing_portal_path
        expect(response).to redirect_to("https://billing.stripe.com/session/test123")
        expect(Stripe::BillingPortal::Session).to have_received(:create).with(
          customer: "cus_test123",
          return_url: billing_url
        )
      end
    end

    context "without Stripe customer ID but with paid plan" do
      # Basic-only Stripe trials (Billing::TrialPolicy); Pro/Upgraded never get trial_period_days in Checkout.
      let(:basic_plan) { create(:pricing_plan, name: "Basic", price: 9.99) }
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: basic_plan, status: :trialing,
               trial_ends_at: 7.days.from_now, started_at: 1.week.ago)
      end

      before do
        # Set stripe_price_id on the plan
        basic_plan.update(stripe_price_id: "price_test123")
        # Mock Stripe Checkout session creation
        allow(Stripe::Checkout::Session).to receive(:create).and_return(
          double(url: "https://checkout.stripe.com/session/test123", id: "cs_test123")
        )
      end

      it "creates Stripe Checkout session and redirects" do
        post billing_portal_path
        expect(response).to redirect_to("https://checkout.stripe.com/session/test123")
        expect(Stripe::Checkout::Session).to have_received(:create)
      end

      it "passes correct parameters to Stripe" do
        post billing_portal_path
        
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(
            mode: "subscription",
            line_items: [{ price: "price_test123", quantity: 1 }],
            metadata: { user_id: user.id, plan_id: basic_plan.id }
          )
        )
      end

      it "does not add trial period when user is already in trial on the same plan" do
        post billing_portal_path

        expect(Stripe::Checkout::Session).to have_received(:create).with(
          satisfy do |opts|
            sd = opts[:subscription_data] || {}
            !sd.key?(:trial_period_days)
          end
        )
      end

      context "when user is not in trial" do
        let!(:subscription) do
          create(:subscription, user: user, pricing_plan: basic_plan, status: :active,
                 started_at: 1.week.ago, trial_ends_at: 1.week.ago)
        end

        it "adds Basic-only Stripe trial period days" do
          post billing_portal_path

          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(
              subscription_data: hash_including(trial_period_days: User::STANDARD_TRIAL_PERIOD_DAYS)
            )
          )
        end
      end

      context "with Stripe API error" do
        before do
          error = Stripe::InvalidRequestError.new("Invalid price ID", "price")
          allow(Stripe::Checkout::Session).to receive(:create).and_raise(error)
        end

        it "redirects with error message" do
          post billing_portal_path
          expect(response).to redirect_to(billing_path)
          expect(flash[:alert]).to include("Unable to create payment session")
        end
      end
    end

    context "without Stripe customer ID and without paid plan" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: free_plan, status: :active,
               started_at: 1.week.ago)
      end

      it "redirects to pricing page with alert" do
        post billing_portal_path
        expect(response).to redirect_to(upgrade_pricing_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "without subscription" do
      it "redirects to pricing page with alert" do
        post billing_portal_path
        expect(response).to redirect_to(upgrade_pricing_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "JSON format (Stripe customer on user)" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :trialing,
               trial_ends_at: 7.days.from_now, started_at: 1.week.ago,
               stripe_customer_id: "cus_json_portal")
      end

      before do
        user.update_column(:stripe_customer_id, "cus_json_portal")
        allow(Stripe::BillingPortal::Session).to receive(:create).and_return(
          double(url: "https://billing.stripe.com/json-session")
        )
      end

      it "returns portal url as JSON" do
        post billing_portal_path, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["url"]).to eq("https://billing.stripe.com/json-session")
      end

      it "returns localized error when billing portal session creation fails" do
        allow(Stripe::BillingPortal::Session).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new("bad", "param")
        )
        post billing_portal_path, as: :json
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.portal_session_create_failed"))
      end

      it "returns localized error when Stripe customer creation fails (no customer id)" do
        user.update_column(:stripe_customer_id, nil)
        allow(Stripe::Customer).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new("bad", "param")
        )
        post billing_portal_path, as: :json
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.portal_customer_init_failed"))
      end
    end
  end

  describe "POST /billing/create_checkout_session (checkout)" do
    # Named "Basic" so Billing::TrialPolicy applies STANDARD_TRIAL_PERIOD_DAYS to Checkout subscription_data.
    let!(:paid_plan) { create(:pricing_plan, name: "Basic", price: 14.99, stripe_price_id: "price_monthly_123", stripe_price_id_annual: "price_annual_123") }

    before do
      allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_new123"))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(
        double(url: "https://checkout.stripe.com/session/checkout123")
      )
    end

    context "without stripe_customer_id" do
      it "creates customer and checkout session and returns JSON url" do
        user.update_column(:stripe_customer_id, nil)

        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["url"]).to eq("https://checkout.stripe.com/session/checkout123")
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(line_items: [{ price: "price_monthly_123", quantity: 1 }], subscription_data: hash_including(trial_period_days: User::STANDARD_TRIAL_PERIOD_DAYS))
        )
      end
    end

    context "with stripe_customer_id" do
      before { user.update_column(:stripe_customer_id, "cus_existing") }

      it "returns 400 when price_id is missing" do
        post billing_checkout_path, params: {}, as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.checkout_price_id_required"))
      end

      it "creates checkout session when price_id matches plan monthly price" do
        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(customer: "cus_existing", line_items: [{ price: "price_monthly_123", quantity: 1 }])
        )
      end

      it "creates checkout session when price_id matches plan annual price (find_by_stripe_price)" do
        post billing_checkout_path, params: { price_id: "price_annual_123" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(line_items: [{ price: "price_annual_123", quantity: 1 }])
        )
      end
    end

    context "when user already has active Stripe subscription (non-trial)" do
      before do
        user.update_column(:stripe_customer_id, "cus_existing")
        user.update_column(:stripe_subscription_id, "sub_active")
        # No trialing subscription: current_subscription is not trialing, so trial_active? is false
        create(:subscription, user: user, pricing_plan: paid_plan, status: :active, started_at: 1.week.ago, trial_ends_at: 1.week.ago)
      end

      it "returns 400 and does not create session" do
        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.checkout_active_subscription_use_portal"))
        expect(Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context "when user has stripe_subscription_id but is in trial" do
      before do
        user.update_column(:stripe_customer_id, "cus_existing")
        user.update_column(:stripe_subscription_id, "sub_trial")
        create(:subscription, user: user, pricing_plan: paid_plan, status: :trialing, trial_ends_at: 7.days.from_now, started_at: 1.week.ago, stripe_subscription_id: "sub_trial")
      end

      it "allows checkout and creates session (trial users can set up payment)" do
        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["url"]).to eq("https://checkout.stripe.com/session/checkout123")
        expect(Stripe::Checkout::Session).to have_received(:create)
      end
    end

    context "when Stripe raises InvalidRequestError" do
      before do
        user.update_column(:stripe_customer_id, "cus_existing")
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new("No such price", "price")
        )
      end

      it "returns 422 with localized JSON error and does not expose 500" do
        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["error"]).to eq(I18n.t("controllers.billing.checkout_payment_setup_failed"))
      end
    end

    context "when Checkout::Session.create raises a non-Stripe error" do
      before do
        user.update_column(:stripe_customer_id, "cus_existing")
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(StandardError, "unexpected")
      end

      it "returns 500 with localized JSON error" do
        post billing_checkout_path, params: { price_id: "price_monthly_123" }, as: :json
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.checkout_failed"))
      end
    end
  end

  describe "POST /billing/change_plan" do
    let(:basic_plan) do
      create(:pricing_plan, name: "Basic", display_order: 1, stripe_price_id: "price_basic", price_display: "$10")
    end
    let(:upgraded_plan) do
      create(:pricing_plan, name: "Upgraded", display_order: 2, stripe_price_id: "price_upgraded", price_display: "$20")
    end
    let!(:stripe_sub_record) do
      create(:subscription,
        user: user,
        pricing_plan: basic_plan,
        status: :active,
        started_at: 1.day.ago,
        stripe_subscription_id: "sub_change_test",
        stripe_customer_id: "cus_change_test")
    end

    it "returns unprocessable when no Stripe subscription on file" do
      stripe_sub_record.update_column(:stripe_subscription_id, nil)
      post billing_change_plan_path,
        params: { plan_id: upgraded_plan.id, interval: "month" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates Stripe with always_invoice when upgrading tiers" do
      item = double("Item", id: "si_line", price: double(id: "price_basic"))
      stripe_sub = double(
        "Stripe::Subscription",
        id: "sub_change_test",
        status: "active",
        customer: "cus_change_test",
        items: double(data: [ item ])
      )
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_change_test").and_return(stripe_sub)
      expect(Stripe::Subscription).to receive(:update).with(
        "sub_change_test",
        hash_including(
          proration_behavior: "always_invoice",
          payment_behavior: "error_if_incomplete",
          items: [ { id: "si_line", price: "price_upgraded" } ]
        )
      )
      post billing_change_plan_path,
        params: { plan_id: upgraded_plan.id, interval: "month" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_url"]).to be_present
    end

    it "returns JSON unprocessable when plan_id does not resolve to an active plan" do
      post billing_change_plan_path,
        params: { plan_id: 0, interval: "month" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "returns JSON unprocessable when the plan exists but is inactive" do
      inactive = create(:pricing_plan,
        name: "BillingSpec Inactive Target",
        display_order: 991,
        active: false,
        stripe_price_id: "price_inactive_target",
        price: 9.99)

      post billing_change_plan_path,
        params: { plan_id: inactive.id, interval: "month" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "redirects HTML to billing with alert when plan_id does not resolve to an active plan" do
      post billing_change_plan_path, params: { plan_id: 0, interval: "month" }
      expect(response).to redirect_to(billing_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "redirects HTML to billing with alert when the plan exists but is inactive" do
      inactive_html = create(:pricing_plan,
        name: "BillingSpec Inactive Target HTML",
        display_order: 993,
        active: false,
        stripe_price_id: "price_inactive_html",
        price: 7.99)

      post billing_change_plan_path, params: { plan_id: inactive_html.id, interval: "month" }
      expect(response).to redirect_to(billing_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end
  end

  describe "GET /billing/preview_plan_change" do
    let(:basic_plan) { create(:pricing_plan, name: "Basic", display_order: 1, stripe_price_id: "price_basic") }
    let(:upgraded_plan) { create(:pricing_plan, name: "Upgraded", display_order: 2, stripe_price_id: "price_upgraded") }
    let!(:stripe_sub_record) do
      create(:subscription, user: user, pricing_plan: basic_plan, status: :active, started_at: 1.day.ago,
        stripe_subscription_id: "sub_preview", stripe_customer_id: "cus_preview")
    end

    it "returns amount preview JSON" do
      item = double("Item", id: "si_line", price: double(id: "price_basic"))
      stripe_sub = double("Stripe::Subscription", id: "sub_preview", customer: "cus_preview", items: double(data: [ item ]))
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_preview").and_return(stripe_sub)
      inv = double("Invoice", amount_due: 499, currency: "usd")
      allow(Stripe::Invoice).to receive(:upcoming).and_return(inv)

      get billing_preview_plan_change_path, params: { plan_id: upgraded_plan.id, interval: "month" },
        headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["amount_due"]).to eq(499)
      expect(response.parsed_body["formatted"]).to be_present
    end

    it "returns JSON not_found when plan_id does not resolve to an active plan" do
      get billing_preview_plan_change_path, params: { plan_id: 0, interval: "month" },
        headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "returns JSON not_found when the plan exists but is inactive" do
      inactive = create(:pricing_plan,
        name: "BillingSpec Inactive Preview",
        display_order: 992,
        active: false,
        stripe_price_id: "price_inactive_preview",
        price: 8.99)

      get billing_preview_plan_change_path, params: { plan_id: inactive.id, interval: "month" },
        headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "redirects HTML to billing with alert when plan_id does not resolve to an active plan" do
      get billing_preview_plan_change_path, params: { plan_id: 0, interval: "month" }
      expect(response).to redirect_to(billing_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end

    it "redirects HTML to billing with alert when the plan exists but is inactive" do
      inactive_html = create(:pricing_plan,
        name: "BillingSpec Inactive Preview HTML",
        display_order: 994,
        active: false,
        stripe_price_id: "price_inactive_preview_html",
        price: 6.99)

      get billing_preview_plan_change_path, params: { plan_id: inactive_html.id, interval: "month" }
      expect(response).to redirect_to(billing_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.billing.plan_not_found"))
    end
  end

  describe "POST /billing/cancel_subscription" do
    context "when the current subscription has no Stripe subscription id" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
      end

      it "redirects to billing with an alert (HTML)" do
        post billing_cancel_subscription_path

        expect(response).to redirect_to(billing_path)
        expect(flash[:alert]).to eq(I18n.t("controllers.billing.no_stripe_subscription"))
      end

      it "returns 422 JSON" do
        post billing_cancel_subscription_path, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.no_stripe_subscription"))
      end
    end

    context "when the current subscription is paid in Stripe and outside the refund window" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: paid_plan,
          status: :active,
          started_at: 2.months.ago,
          stripe_subscription_id: "sub_billing_cancel_req",
          first_paid_invoice_at: 10.days.ago
        )
      end

      before do
        stripe_sub = double("Stripe::Subscription", id: "sub_billing_cancel_req")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_billing_cancel_req").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:update).with("sub_billing_cancel_req", { cancel_at_period_end: true })
      end

      it "redirects with the period-end cancellation notice (HTML)" do
        post billing_cancel_subscription_path

        expect(response).to redirect_to(billing_path)
        expect(flash[:notice]).to eq(I18n.t("controllers.billing.canceled_at_period_end"))
      end

      it "returns JSON with message and billing redirect URL" do
        post billing_cancel_subscription_path, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["message"]).to eq(I18n.t("controllers.billing.canceled_at_period_end"))
        expect(response.parsed_body["redirect_url"]).to be_present
      end
    end
  end

  describe "POST /billing/resume_subscription" do
    context "when the current subscription has no Stripe subscription id" do
      let!(:subscription) do
        create(:subscription, user: user, pricing_plan: paid_plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
      end

      it "redirects to billing with an alert (HTML)" do
        post billing_resume_subscription_path

        expect(response).to redirect_to(billing_path)
        expect(flash[:alert]).to eq(I18n.t("controllers.billing.no_stripe_subscription"))
      end

      it "returns 422 JSON" do
        post billing_resume_subscription_path, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.billing.no_stripe_subscription"))
      end
    end

    context "when the current subscription has a Stripe subscription id" do
      let!(:subscription) do
        create(
          :subscription,
          user: user,
          pricing_plan: paid_plan,
          status: :active,
          started_at: Time.current,
          stripe_subscription_id: "sub_billing_resume_req"
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:update).with("sub_billing_resume_req", { cancel_at_period_end: false })
      end

      it "redirects with the resumed notice (HTML)" do
        post billing_resume_subscription_path

        expect(response).to redirect_to(billing_path)
        expect(flash[:notice]).to eq(I18n.t("controllers.billing.subscription_resumed"))
      end

      it "returns JSON success" do
        post billing_resume_subscription_path, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["message"]).to eq(I18n.t("controllers.billing.subscription_resumed"))
      end
    end
  end
end

