# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild show (dashboard)", type: :request do
  let(:owner) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner, description: "", discord_invite_url: nil) }
  let(:member) { create(:user, auth_method: :discord) }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

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
    create(:guild_member, guild: guild, user: member, status: :active, discord_role_id: "role-1")
    member.subscribe_to_plan!(basic_plan)
    guild.update!(
      permission_role_1_id: "role-1",
      role_1_can_view_activity_feed: true,
      role_1_can_manage_guild_settings: true
    )
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in member
  end

  describe "support_center_url in signed-in guild chrome" do
    it "includes default support URL in HTML" do
      get guild_path(guild)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://guild-show-sidebar-support.example/help")
      get guild_path(guild)
      expect(response.body).to include("https://guild-show-sidebar-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://guild-show-sidebar-support.example/help")
      get guild_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://guild-show-sidebar-support.example/help")
    end
  end

  it "renders quick actions that mirror key sidebar destinations" do
    get guild_path(guild)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(guild_members_list_path(guild))
    expect(response.body).to include(guild_polls_path(guild))
    expect(response.body).to include(I18n.t("sidebar.guild_menu.members"))
  end

  it "shows public Discord invite when configured" do
    guild.update!(discord_invite_url: "https://discord.gg/testguildshow")
    get guild_path(guild)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://discord.gg/testguildshow")
    expect(response.body).to include(I18n.t("guilds.show.join_discord"))
  end

  it "shows no-description fallback when description is blank" do
    get guild_path(guild)
    expect(response.body).to include(I18n.t("guilds.show.no_description"))
  end

  describe "PATCH guild profile from settings" do
    it "persists description and discord_invite_url" do
      patch update_guild_path(guild), params: {
        guild: {
          description: "We raid weekends.",
          discord_invite_url: "https://discord.gg/savedlink"
        }
      }
      expect(response).to redirect_to(guild_settings_path(guild))
      guild.reload
      expect(guild.description).to eq("We raid weekends.")
      expect(guild.discord_invite_url).to eq("https://discord.gg/savedlink")
    end

    it "rejects non-http(s) invite URLs" do
      patch update_guild_path(guild), params: {
        guild: { discord_invite_url: "ftp://example.com/x" }
      }
      expect(response).to redirect_to(guild_settings_path(guild))
      follow_redirect!
      expect(response.body).to match(/invalid|Invalid|failed|Failed/i)
      expect(guild.reload.discord_invite_url).to be_nil
    end
  end
end
