# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidebar member guild AI gear scanner", type: :request do
  let(:owner) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member) { create(:user, auth_method: :discord) }
  let!(:membership) do
    create(:guild_member, guild: guild, user: member, status: :active, discord_role_id: "role-1")
  end

  let(:elite_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "elite").first ||
      create(:pricing_plan,
        name: "Elite",
        price: 25,
        price_display: "$25",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: 500,
        active: true,
        display_order: 98)
  end

  let(:basic_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "basic").first ||
      create(:pricing_plan,
        name: "Basic",
        price: 9,
        price_display: "$9",
        period: "per month",
        max_guilds: 5,
        max_members_per_guild: 100,
        active: true,
        display_order: 91)
  end

  before do
    member.subscribe_to_plan!(elite_plan)
    sign_in member
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  it "includes AI Gear Scanner link for a non-owner guild member when plan allows it" do
    get dashboard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(guild_members_gear_path(guild))
    expect(response.body).to include(I18n.t("sidebar.guild_menu.members_gear"))
  end

  it "includes AI Gear Scanner link on mobile variant" do
    get dashboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(guild_members_gear_path(guild))
  end

  context "when plan does not include ai_gear_scanner" do
    before do
      member.subscriptions.destroy_all
      member.subscribe_to_plan!(basic_plan)
      member.reload
    end

    it "omits the link from the member guild menu" do
      get dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(guild_members_gear_path(guild))
    end
  end

  context "when the member is on Basic but the guild owner has Upgraded (shared stat scanner)" do
    let(:upgraded_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
        create(:pricing_plan,
          name: "Upgraded",
          price: 16,
          price_display: "$16",
          period: "per month",
          max_guilds: nil,
          max_members_per_guild: nil,
          active: true,
          display_order: 97)
    end

    before do
      owner.subscribe_to_plan!(upgraded_plan)
      member.subscriptions.destroy_all
      member.subscribe_to_plan!(basic_plan)
      member.reload
    end

    it "still shows the stat scanner link for that guild" do
      get dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(guild_members_gear_path(guild))
    end
  end
end
