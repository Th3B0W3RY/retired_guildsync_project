# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild custom role permissions expansion", type: :request do
  let(:basic_plan) { create(:pricing_plan, name: "Basic", price: 8.99, max_guilds: 10, active: true) }
  let(:owner) { create(:user, auth_method: :discord, skip_free_plan_subscription: true) }
  let(:guild) { create(:guild, owner: owner) }
  let(:officer) { create(:user, auth_method: :discord, skip_free_plan_subscription: true) }
  let!(:owner_subscription) { create(:subscription, user: owner, pricing_plan: basic_plan, status: :active) }
  let!(:officer_subscription) { create(:subscription, user: officer, pricing_plan: basic_plan, status: :active) }
  let!(:officer_membership) { create(:guild_member, guild: guild, user: officer, status: :active, discord_role_id: "role-1") }

  before do
    guild.update!(
      permission_role_1_id: "role-1",
      role_1_can_manage_roles: true
    )
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in officer
  end

  it "blocks CSV export without explicit permission" do
    get guild_members_list_path(guild, format: :csv)
    expect(response).to redirect_to(guild_members_list_path(guild))
  end

  it "allows CSV export with explicit permission" do
    guild.update!(role_1_can_export_members_csv: true)
    get guild_members_list_path(guild, format: :csv)
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/csv")
  end

  it "blocks message center without explicit permission" do
    get guild_message_center_path(guild)
    expect(response).to redirect_to(guild_path(guild))
  end

  it "allows message center with explicit permission" do
    guild.update!(role_1_can_use_message_center: true)
    get guild_message_center_path(guild)
    expect(response).to have_http_status(:success)
  end

  it "blocks activity feed without explicit permission" do
    get guild_activity_feed_path(guild)
    expect(response).to redirect_to(guild_path(guild))
  end

  it "allows activity feed with explicit permission" do
    guild.update!(role_1_can_view_activity_feed: true)
    get guild_activity_feed_path(guild)
    expect(response).to have_http_status(:success)
  end

  it "blocks discord event management without explicit permission" do
    get new_guild_discord_event_path(guild)
    expect(response).to redirect_to(guild_path(guild))
  end

  it "allows discord event management gate with explicit permission" do
    guild.update!(role_1_can_manage_events: true)
    get new_guild_discord_event_path(guild)
    expect(response).not_to redirect_to(guild_path(guild))
  end
end
