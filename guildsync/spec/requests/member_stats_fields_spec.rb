# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member stats field edits", type: :request do
  let(:owner) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member) { create(:user, auth_method: :discord) }
  let(:other) { create(:user, auth_method: :discord) }
  let(:officer) { create(:user, auth_method: :discord) }
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
    create(:guild_member, guild: guild, user: member, status: :active, discord_role_id: "role-member")
    create(:guild_member, guild: guild, user: other, status: :active, discord_role_id: "role-member")
    create(:guild_member, guild: guild, user: officer, status: :active, discord_role_id: "role-officer")
    member.subscribe_to_plan!(elite_plan)
    other.subscribe_to_plan!(elite_plan)
    officer.subscribe_to_plan!(elite_plan)
    owner.subscribe_to_plan!(elite_plan)
    sign_in member
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  let!(:snapshot) do
    create(:gear_snapshot,
      guild: guild,
      user: member,
      game: game,
      source: :web,
      data: { "Stamina" => "42", "Power" => "9001" })
  end

  it "denies when the member tries to edit their own scanned stats" do
    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "remove", stat_key: "Stamina" },
      as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["message"]).to eq(I18n.t("guilds.member_stats.cannot_edit_scanned_stats"))
    expect(snapshot.reload.data).to include("Stamina")
  end

  it "denies when another member has only manage-gear-requests (not edit-scanned-stats)" do
    guild.update!(
      permission_role_1_id: "role-officer",
      role_1_can_manage_gear_requests: true,
      role_1_can_edit_gear_scanned_stats: false
    )
    sign_in officer
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "remove", stat_key: "Stamina" },
      as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["message"]).to eq(I18n.t("guilds.member_stats.cannot_edit_scanned_stats"))
    expect(snapshot.reload.data).to include("Stamina")
  end

  it "allows an officer with can_edit_gear_scanned_stats to edit another member's snapshot" do
    guild.update!(
      permission_role_1_id: "role-officer",
      role_1_can_manage_gear_requests: false,
      role_1_can_edit_gear_scanned_stats: true
    )
    sign_in officer
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "remove", stat_key: "Stamina" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(snapshot.reload.data).to eq("Power" => "9001")
  end

  it "denies when an officer with edit permission tries to fix their own scanned stats" do
    officer_snap = create(:gear_snapshot,
      guild: guild,
      user: officer,
      game: game,
      source: :web,
      data: { "Might" => "10" })
    guild.update!(
      permission_role_1_id: "role-officer",
      role_1_can_edit_gear_scanned_stats: true
    )
    sign_in officer
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: officer.id),
      params: { op: "remove", stat_key: "Might" },
      as: :json

    expect(response).to have_http_status(:forbidden)
    expect(officer_snap.reload.data).to include("Might")
  end

  it "returns forbidden when another member without edit permission tries to edit someone else's snapshot" do
    sign_in other
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "remove", stat_key: "Stamina" },
      as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["message"]).to eq(I18n.t("guilds.member_stats.cannot_edit_scanned_stats"))
    expect(snapshot.reload.data).to include("Stamina")
  end

  it "allows the guild owner to edit a member's snapshot" do
    sign_in owner
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "remove", stat_key: "Power" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(snapshot.reload.data).not_to have_key("Power")
  end

  it "allows the guild owner to edit their own snapshot" do
    owner_snap = create(:gear_snapshot,
      guild: guild,
      user: owner,
      game: game,
      source: :web,
      data: { "GS" => "100" })
    sign_in owner
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: owner.id),
      params: { op: "remove", stat_key: "GS" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(owner_snap.reload.data).to eq({})
  end

  it "restores a removed field when editor is guild owner" do
    snapshot.update!(data: { "Power" => "9001" })
    sign_in owner
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: { op: "restore", stat_key: "Stamina", stat_value: "42" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(snapshot.reload.data["Stamina"]).to eq("42")
  end

  it "updates a stat label and value as JSON when editor is guild owner" do
    sign_in owner
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

    patch guild_member_stats_fields_path(guild, user_id: member.id),
      params: {
        op: "update",
        stat_key: "Stamina",
        stat_label: "Focus",
        stat_value: "1961 (5.6%)"
      },
      as: :json

    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json["ok"]).to eq(true)
    expect(json["stat_key"]).to eq("Focus")
    expect(json["display_label"]).to eq("Focus")
    expect(json["display_value"]).to eq("1961 (5.6%)")
    expect(snapshot.reload.data["Focus"]).to eq("1961 (5.6%)")
    expect(snapshot.data).not_to have_key("Stamina")
  end
end
