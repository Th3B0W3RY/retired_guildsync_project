# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Plan entitlements matrix", type: :request do
  let(:upgrade_alert) { I18n.t("plan_entitlements.upgrade_required") }

  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }

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

  let(:elite_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "elite").first ||
      create(:pricing_plan,
        name: "Elite",
        price: 29,
        price_display: "$29",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: nil,
        active: true,
        display_order: 99)
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "guild owner on the Free plan" do
    before { sign_in owner }

    it "redirects activity feed to upgrade pricing" do
      get guild_activity_feed_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects message center to upgrade pricing" do
      get guild_message_center_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects guild warnings to upgrade pricing" do
      get guild_warnings_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects guild documents to upgrade pricing" do
      get guild_documents_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects guild storage to upgrade pricing" do
      get guild_storage_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects members gear (AI gear) to upgrade pricing" do
      get guild_members_gear_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end
  end

  describe "guild owner on Basic" do
    before do
      owner.subscribe_to_plan!(basic_plan)
      sign_in owner
    end

    it "allows activity feed" do
      get guild_activity_feed_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows message center" do
      get guild_message_center_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows guild warnings" do
      get guild_warnings_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "redirects guild documents to upgrade pricing" do
      get guild_documents_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects guild storage to upgrade pricing" do
      get guild_storage_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end

    it "redirects members gear (AI gear) to upgrade pricing" do
      get guild_members_gear_path(guild)
      expect(response).to redirect_to(upgrade_pricing_path)
      expect(flash[:alert]).to eq(upgrade_alert)
    end
  end

  describe "guild owner on Upgraded" do
    before do
      owner.subscribe_to_plan!(upgraded_plan)
      sign_in owner
    end

    it "allows guild documents" do
      get guild_documents_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows guild storage" do
      get guild_storage_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows members gear (AI gear)" do
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "guild owner on Elite" do
    before do
      owner.subscribe_to_plan!(elite_plan)
      sign_in owner
    end

    it "allows activity feed" do
      get guild_activity_feed_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows message center" do
      get guild_message_center_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows guild warnings" do
      get guild_warnings_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows guild documents" do
      get guild_documents_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows guild storage" do
      get guild_storage_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "allows members gear (AI gear)" do
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "guild member on Free when guild owner is on Upgraded" do
    let(:member) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
    let(:free_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "free").first ||
        create(:pricing_plan, name: "Free", price: 0, max_guilds: 1, max_members_per_guild: 5, active: true, display_order: 1)
    end

    before do
      owner.subscribe_to_plan!(upgraded_plan)
      member.subscribe_to_plan!(free_plan)
      create(:guild_member, guild: guild, user: member, status: :active)
      sign_in member
    end

    it "allows members gear via the guild owner's stat scanner entitlement" do
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
    end
  end
end
