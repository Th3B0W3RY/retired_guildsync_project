# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Pricing and Subscriptions", type: :request do
  let(:user) do
    u = create(:user)
    # Set auth_method to "discord" to bypass MFA checks in tests
    # This matches how the application handles Discord-authenticated users
    u.update!(auth_method: "discord")
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let(:free_plan) { PricingPlan.find_or_create_by!(name: "Free") { |p| p.price_display = "$0"; p.max_guilds = 1; p.price = 0; p.period = "forever"; p.active = true } }
  let(:paid_plan) { create(:pricing_plan, name: "Pro", price_display: "$10", max_guilds: 10) }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  describe "GET /pricing" do
    context "when user is not signed in" do
      it "shows public pricing page" do
        get "/pricing"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Free")
      end

      it "includes Stimulus pricing-plans markup when a paid plan has annual Stripe pricing" do
        create(:pricing_plan,
               name: "PublicAnnualSpec",
               period: "month",
               price: 10,
               price_display: "$10",
               stripe_price_id: "price_public_m",
               stripe_price_id_annual: "price_public_y",
               display_order: 96,
               active: true,
               max_guilds: 3)
        get "/pricing"

        expect(response.body).to include('data-controller="pricing-plans"')
        expect(response.body).to include('data-pricing-plans-target="intervalToggle"')
      end

      it "keeps annual price hidden in HTML on outer row (no hidden + inline-flex Tailwind clash)" do
        create(:pricing_plan,
               name: "PublicAnnualDisplaySpec",
               period: "month",
               price: 10,
               price_display: "$10",
               stripe_price_id: "price_pub_disp_m",
               stripe_price_id_annual: "price_pub_disp_y",
               display_order: 95,
               active: true,
               max_guilds: 3)
        get "/pricing"
        doc = Nokogiri::HTML(response.body)
        doc.css(".pricing-price-wrap").each do |wrap|
          annual = wrap.at_css(".price-annual")
          next unless annual

          classes = annual["class"].to_s.split
          expect(classes).to include("hidden"),
            "annual row must start hidden so only one interval shows until the toggle runs"
          expect(classes).not_to include("inline-flex"),
            "do not mix inline-flex on the same node as hidden — Tailwind can leave annual prices visible"
          monthly = wrap.at_css(".price-monthly")
          expect(monthly["class"].to_s.split).not_to include("inline-flex")
        end
      end
    end

    context "when user is signed in" do
      before { sign_in user }

      it "redirects to upgrade pricing page" do
        get "/pricing"
        
        expect(response).to redirect_to(upgrade_pricing_path)
      end

      it "redirects to upgrade pricing page when accessing /pricing" do
        set_mfa_verified_in_session
        get "/pricing"
        
        expect(response).to redirect_to(upgrade_pricing_path)
      end

      it "shows upgrade pricing page" do
        set_mfa_verified_in_session
        get "/pricing/upgrade"
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Free")
      end

      it "includes Stimulus pricing-plans markup when a paid plan has annual Stripe pricing" do
        create(:pricing_plan,
               name: "UpgradeAnnualSpec",
               period: "month",
               price: 12,
               price_display: "$12",
               stripe_price_id: "price_upgrade_m",
               stripe_price_id_annual: "price_upgrade_y",
               display_order: 97,
               active: true,
               max_guilds: 5)
        set_mfa_verified_in_session
        get "/pricing/upgrade"

        expect(response.body).to include('data-controller="pricing-plans"')
        expect(response.body).to include('data-pricing-plans-target="intervalToggle"')
      end

      it "includes support center URL in upgrade page contact copy" do
        set_mfa_verified_in_session
        get upgrade_pricing_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes support center URL in upgrade page contact copy on mobile variant" do
        set_mfa_verified_in_session
        get upgrade_pricing_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL in upgrade page when set" do
        SiteSetting.set("release_notes_url", "https://pricing-upgrade-support.example/help")
        set_mfa_verified_in_session
        get upgrade_pricing_path
        expect(response.body).to include("https://pricing-upgrade-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://pricing-upgrade-support.example/help")
        set_mfa_verified_in_session
        get upgrade_pricing_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://pricing-upgrade-support.example/help")
      end
    end
  end

  describe "POST /pricing/select_plan/:id" do
    before do
      sign_in user
      # Create a subscription for the user
      create(:subscription, user: user, pricing_plan: free_plan) unless user.subscriptions.any?
    end

    context "with free plan" do
      it "switches to free plan" do
        set_mfa_verified_in_session
        
        post "/pricing/select_plan/#{free_plan.id}"
        
        expect(response).to redirect_to(upgrade_pricing_path)
        expect(flash[:notice]).to include("Free plan")
      end
    end

    context "with paid plan" do
      before do
        # User is on free plan
        user.subscriptions.destroy_all
        create(:subscription, user: user, pricing_plan: free_plan)
      end

      it "redirects appropriately for paid plan" do
        set_mfa_verified_in_session
        
        post "/pricing/select_plan/#{paid_plan.id}"
        
        # If user can start trial, redirects to upgrade_pricing_path
        # If user has used trial, redirects to subscribe_path
        expect(response).to be_redirect
        expect(response.location).to match(/(subscribe|pricing\/upgrade)/)
      end
    end
  end

  describe "Subscription enforcement" do
    let!(:free_subscription) { create(:subscription, user: user, pricing_plan: free_plan) }

    before do
      sign_in user
    end

    it "enforces max_guilds limit" do
      # Ensure user only has the free subscription (remove any other subscriptions)
      user.subscriptions.where.not(pricing_plan: free_plan).destroy_all
      user.reload
      
      # Free plan allows 1 guild
      create(:guild, owner: user)
      
      # Verify user has reached the limit
      expect(user.owned_guilds.count).to eq(1)
      expect(user.can_create_guild?).to be false
      
      # Create a test game for guild creation
      test_game = Game.find_or_create_by!(name: "Test Game", slug: "test-game") do |g|
        g.description = "Default test game"
        g.active = true
        g.ocr_config = {}
      end
      
      expect {
        post "/guilds", params: {
          guild: {
            name: "Second Guild",
            description: "Should fail",
            game_ids: [test_game.id],
            primary_game_id: test_game.id
          }
        }
      }.not_to change { Guild.count }
      
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to include("Guild limit reached")
    end
  end
end

