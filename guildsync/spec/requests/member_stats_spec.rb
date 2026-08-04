# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member stat snapshot page", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:owner) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member) { create(:user, auth_method: :discord) }
  let(:game) { guild.games.first }

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

  before do
    create(:guild_member, guild: guild, user: member, status: :active, discord_role_id: "role-1")
    member.subscribe_to_plan!(elite_plan)
    sign_in member
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  it "uses the later of created_at and updated_at for the last-updated line" do
    travel_to Time.zone.parse("2026-04-16 12:00:00") do
      snapshot = create(:gear_snapshot,
        guild: guild,
        user: member,
        game: game,
        source: :web,
        data: { "Stamina" => "1" })
      snapshot.update_columns(created_at: 30.days.ago, updated_at: Time.current)

      get guild_member_stats_path(guild, user_id: member.id)

      expect(response).to have_http_status(:ok)
      fragment = ApplicationController.helpers.time_ago_in_words(Time.current)
      expect(response.body).to include(fragment)
    end
  end

  it "renders structured stats for a member with a snapshot" do
    create(:gear_snapshot,
      guild: guild,
      user: member,
      game: game,
      source: :web,
      data: { "Stamina" => "42", "Power" => "9001" })

    get guild_member_stats_path(guild, user_id: member.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stamina")
    expect(response.body).to include("42")
    expect(response.body).to include(I18n.t("guilds.member_stats.extracted_heading"))
    expect(response.body).not_to match(/"Stamina"\s*:/)
    # Members cannot edit their own scanned stats — no interactive Stimulus row.
    expect(response.body).not_to include('data-controller="member-stat-row"')
  end

  it "shows editable stat rows when the guild owner views a member's snapshot" do
    create(:gear_snapshot,
      guild: guild,
      user: member,
      game: game,
      source: :web,
      data: { "Stamina" => "42" })
    owner.subscribe_to_plan!(elite_plan)
    sign_in owner
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    get guild_member_stats_path(guild, user_id: member.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="member-stat-row"')
  end

  it "allows a Free-plan member when the guild owner has the stat scanner entitlement" do
    skip "User has no subscription columns" unless member.respond_to?(:subscriptions)

    free_plan = PricingPlan.where("LOWER(TRIM(name)) = ?", "free").first ||
      create(:pricing_plan, name: "Free", price: 0, max_guilds: 1, max_members_per_guild: 5, active: true, display_order: 1)
    upgraded_plan = PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
      create(:pricing_plan,
        name: "Upgraded",
        price: 16,
        price_display: "$16",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: nil,
        active: true,
        display_order: 97)

    owner.subscribe_to_plan!(upgraded_plan)
    member.subscriptions.destroy_all
    member.subscribe_to_plan!(free_plan)
    member.reload

    get guild_member_stats_path(guild, user_id: member.id)
    expect(response).to have_http_status(:ok)
  end

  it "denies access when the viewer is not a member of the guild" do
    outsider = create(:user, auth_method: :discord)
    outsider.subscribe_to_plan!(elite_plan)
    sign_in outsider
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    get guild_member_stats_path(guild, user_id: member.id)

    expect(response).to redirect_to(my_guilds_path)
  end

  it "redirects when a member tries to view another member's stats" do
    peer = create(:user, auth_method: :discord)
    peer.subscribe_to_plan!(elite_plan)
    create(:guild_member, guild: guild, user: peer, status: :active, discord_role_id: "role-2")
    create(:gear_snapshot,
      guild: guild,
      user: member,
      game: game,
      source: :web,
      data: { "Stamina" => "42" })

    sign_in peer
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    get guild_member_stats_path(guild, user_id: member.id)

    expect(response).to redirect_to(guild_members_gear_path(guild))
    expect(flash[:alert]).to eq(I18n.t("guilds.member_stats.cannot_view_other_member_stats"))
  end
end
