# frozen_string_literal: true

require "rails_helper"
require "erb"

RSpec.describe "Admin::PricingPlanFeatures", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  def pricing_plan_form_fields(plan)
    {
      name: plan.name,
      period: plan.period,
      description: plan.description.to_s,
      display_order: plan.display_order.to_s
    }
  end

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/pricing-plan-features" do
    it "renders edit form" do
      plan = create(:pricing_plan, name: "FeaturesSpecPlan", features: [ "A", "B" ], period: "month", display_order: 50,
        price: 12, price_display: "$12")
      get "/admin/pricing-plan-features"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.pricing_plan_features.page_title"))
      expect(response.body).to include("A\nB")
      expect(response.body).to include("plan_features_#{plan.id}")
      expect(response.body).to include("plan_price_display_#{plan.id}")
      expect(response.body).to include(I18n.t("admin.pricing_plan_features.entitlements_section_title"))
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      plan = create(:pricing_plan, name: "FrameSpecPlan", features: [ "X" ], period: "month", display_order: 52,
        price: 9, price_display: "$9")

      get "/admin/pricing-plan-features",
        headers: { "Turbo-Frame" => Admin::PricingPlanFeaturesController::PRICING_PLAN_FEATURES_EDIT_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_pricing_plan_features_main"))
      expect(response.body).to include("plan_features_#{plan.id}")
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("admin.pricing_plan_features.page_title")))
    end
  end

  describe "PATCH /admin/pricing-plan-features" do
    it "updates features jsonb for each submitted plan" do
      plan = create(:pricing_plan, name: "PatchFeaturesPlan", features: [ "old" ], period: "month", display_order: 51,
        price: 10, price_display: "$10")

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => pricing_plan_form_fields(plan).merge(
            features_text: "One feature\nTwo feature\n",
            price_display: "$10",
            price_monthly: "10",
            price_display_annual: ""
          )
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      expect(flash[:notice]).to eq(I18n.t("admin.pricing_plan_features.updated"))
      expect(plan.reload.features).to eq([ "One feature", "Two feature" ])
    end

    it "persists feature_entitlements when entitlements are submitted" do
      plan = create(:pricing_plan, name: "PatchEntitlementsPlan", features: [ "x" ], period: "month", display_order: 53,
        price: 11, price_display: "$11", feature_entitlements: {})

      ent = PlanEntitlementService.feature_flag_keys.index_with { |_k| "0" }
      ent["ai_gear_scanner"] = "1"

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => pricing_plan_form_fields(plan).merge(
            features_text: "x",
            price_display: "$11",
            price_monthly: "11",
            price_display_annual: "",
            entitlements: ent
          )
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      expect(plan.reload.feature_entitlements["ai_gear_scanner"]).to be true
    end

    it "updates price_display, price, and annual display" do
      plan = create(:pricing_plan, name: "PatchPricePlan", features: [ "x" ], period: "month", display_order: 52,
        price: 12, price_display: "$12", price_display_annual: nil)

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => pricing_plan_form_fields(plan).merge(
            features_text: "x",
            price_display: "$19",
            price_monthly: "19",
            price_display_annual: "$199"
          )
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      plan.reload
      expect(plan.price_display).to eq("$19")
      expect(plan.price).to eq(BigDecimal("19"))
      expect(plan.price_display_annual).to eq("$199")
    end

    it "rejects invalid monthly amount" do
      plan = create(:pricing_plan, name: "BadPricePlan", features: [ "x" ], period: "month", display_order: 53,
        price: 5, price_display: "$5")

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => pricing_plan_form_fields(plan).merge(
            features_text: "x",
            price_display: "$5",
            price_monthly: "12.3.4",
            price_display_annual: ""
          )
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      expect(flash[:alert]).to eq(I18n.t("admin.pricing_plan_features.invalid_monthly_price"))
      expect(plan.reload.price).to eq(BigDecimal("5"))
    end

    it "wraps RecordInvalid plan errors in validation_error i18n" do
      plan = create(:pricing_plan, name: "BlankDisplayPlan", features: [ "x" ], period: "month", display_order: 54,
        price: 8, price_display: "$8")

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => pricing_plan_form_fields(plan).merge(
            features_text: "x",
            price_display: "",
            price_monthly: "8",
            price_display_annual: ""
          )
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      err_plan = PricingPlan.find(plan.id)
      err_plan.errors.clear
      err_plan.errors.add(:price_display, :blank)
      expected = I18n.t("admin.pricing_plan_features.validation_error", message: err_plan.errors.full_messages.to_sentence)
      expect(flash[:alert]).to eq(expected)
      expect(plan.reload.price_display).to eq("$8")
    end

    it "updates name, period, description, display order, popular, and active" do
      plan = create(:pricing_plan,
        name: "CardMetaPlan",
        description: "Old blurb",
        features: [ "f" ],
        period: "month",
        display_order: 60,
        popular: false,
        active: true,
        price: 10,
        price_display: "$10")

      patch "/admin/pricing-plan-features", params: {
        pricing_plans: {
          plan.id.to_s => {
            name: "Renamed Plan",
            period: "forever",
            description: "New blurb",
            display_order: "5",
            popular: "1",
            active: "0",
            features_text: "f",
            price_display: "$10",
            price_monthly: "10",
            price_display_annual: ""
          }
        }
      }

      expect(response).to redirect_to(admin_edit_pricing_plan_features_path)
      plan.reload
      expect(plan.name).to eq("Renamed Plan")
      expect(plan.period).to eq("forever")
      expect(plan.description).to eq("New blurb")
      expect(plan.display_order).to eq(5)
      expect(plan.popular).to be(true)
      expect(plan.active).to be(false)
    end

    it "returns turbo_stream refresh on successful update" do
      plan = create(:pricing_plan, name: "TurboFeaturesPlan", features: [ "a" ], period: "month", display_order: 70,
        price: 11, price_display: "$11")

      patch "/admin/pricing-plan-features",
        params: {
          pricing_plans: {
            plan.id.to_s => pricing_plan_form_fields(plan).merge(
              features_text: "Line one\nLine two\n",
              price_display: "$11",
              price_monthly: "11",
              price_display_annual: ""
            )
          }
        },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="update"', "admin_pricing_plan_features_flash")
      expect(response.body).to include('action="replace"', "admin_pricing_plan_features_form_wrap")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.pricing_plan_features.updated"))
      )
      expect(response.body).to include("Line one", "Line two")
      expect(plan.reload.features).to eq([ "Line one", "Line two" ])
    end

    it "returns see_other redirect for invalid monthly price when Accept is turbo_stream" do
      plan = create(:pricing_plan, name: "TurboBadPricePlan", features: [ "x" ], period: "month", display_order: 71,
        price: 5, price_display: "$5")

      patch "/admin/pricing-plan-features",
        params: {
          pricing_plans: {
            plan.id.to_s => pricing_plan_form_fields(plan).merge(
              features_text: "x",
              price_display: "$5",
              price_monthly: "12.3.4",
              price_display_annual: ""
            )
          }
        },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/admin/pricing-plan-features")
    end
  end

  describe "authentication" do
    it "redirects to login when not admin" do
      delete "/admin/logout"
      get "/admin/pricing-plan-features"
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
