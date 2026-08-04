# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mobile HTML variant", type: :request do
  let(:user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end

  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let(:guild) { create(:guild, owner: user) }

  before do
    create(:subscription, user: user, pricing_plan: pricing_plan)
    sign_in user
  end

  describe "layout chrome (shell)" do
    it "renders mobile drawer + shell for iPhone User-Agent" do
      get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("mobile-sidebar-panel")
      expect(response.body).to include("data-controller=\"mobile-shell\"")
    end

    it "renders mobile shell for Android mobile User-Agent" do
      get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::ANDROID_CHROME_MOBILE_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("mobile-sidebar-panel")
      expect(response.body).to include("data-controller=\"mobile-shell\"")
    end

    it "does not render mobile-variant sidebar panel id for desktop User-Agent" do
      get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::DESKTOP_CHROME_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("mobile-sidebar-panel")
    end

    it "renders desktop narrow drawer shell (lg breakpoint) for desktop User-Agent on member pages" do
      get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::DESKTOP_CHROME_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("desktop-sidebar-panel")
      expect(response.body).to include("data-controller=\"mobile-shell\"")
    end

    it "does not apply mobile layout variant to /admin HTML (variant skipped for admin paths)" do
      sign_out user
      get "/admin/login", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("mobile-sidebar-panel")
      expect(response.body).not_to include("data-controller=\"mobile-shell\"")
    end
  end

  describe "mobile-specific templates (Tier B markers)" do
    it "dashboard includes Discord widget iframe markup on mobile UA" do
      get "/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("width=\"350\"")
      expect(response.body).to include("height=\"500\"")
      expect(response.body).to include("block max-w-full rounded-lg")
    end

    it "dashboard includes Discord widget iframe on desktop UA (default layout, not mobile-variant panel)" do
      get "/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::DESKTOP_CHROME_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("width=\"350\"")
      expect(response.body).to include("height=\"500\"")
      expect(response.body).to include("block max-w-full rounded-lg")
      expect(response.body).not_to include("mobile-sidebar-panel")
    end

    it "poll vote controls use stacked full-width layout on mobile UA" do
      poll = create(:poll, guild: guild, creator: user)

      get guild_poll_path(guild, poll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("flex w-full flex-col gap-3")
    end
  end
end
