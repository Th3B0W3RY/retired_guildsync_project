# frozen_string_literal: true

require "rails_helper"

# Regression: guild owner must retain full access even when every role_* flag is off and
# permission_role_* slots are unset (Discord role matrix does not apply to the owner).
RSpec.describe "Guild owner trumps role permission flags", type: :request do
  OWNER_TRUMPS_FLAG_SUFFIXES = %w[
    can_manage_roles can_manage_applications can_manage_guild_settings can_kick_members
    can_invite_alliance_guilds can_kick_alliance_guilds can_manage_tags can_manage_warnings
    can_manage_documents can_manage_files can_manage_events can_manage_polls can_manage_loot_rolls
    can_manage_discord_channels can_view_activity_feed can_export_members_csv can_use_message_center
    can_manage_gear_requests can_edit_gear_scanned_stats
  ].freeze

  def strip_guild_role_matrix!(g)
    attrs = {
      permission_role_1_id: nil,
      permission_role_2_id: nil,
      permission_role_3_id: nil,
      permission_role_4_id: nil
    }
    (1..4).each do |n|
      OWNER_TRUMPS_FLAG_SUFFIXES.each { |s| attrs[:"role_#{n}_#{s}"] = false }
    end
    g.update!(attrs)
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

  let(:owner) do
    u = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
    u.save!
    u.subscribe_to_plan!(upgraded_plan)
    u
  end

  let(:guild) { create(:guild, owner: owner) }

  before do
    strip_guild_role_matrix!(guild)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in owner
  end

  it "still reaches the members list" do
    get guild_members_list_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches guild settings" do
    get guild_settings_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches invite / applications UI" do
    get guild_invite_members_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches activity feed (plan + owner bypass)" do
    get guild_activity_feed_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches message center (plan + owner bypass)" do
    get guild_message_center_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches guild warnings (plan + owner bypass)" do
    get guild_warnings_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches guild documents (plan + owner bypass)" do
    get guild_documents_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches guild storage (plan + owner bypass)" do
    get guild_storage_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still reaches members gear (plan + membership)" do
    get guild_members_gear_path(guild)
    expect(response).to have_http_status(:ok)
  end

  it "still allows the owner to PATCH AI stat scanner extracted fields for their own snapshot" do
    snap = create(:gear_snapshot, guild: guild, user: owner, game: guild.games.first, data: { "OwnerKey" => "9" })
    patch guild_member_stats_fields_path(guild, user_id: owner.id),
      params: { op: "remove", stat_key: "OwnerKey" },
      as: :json
    expect(response).to have_http_status(:ok)
    expect(snap.reload.data).to eq({})
  end

  it "still reaches owner-only schedule events" do
    get guild_schedule_events_path(guild)
    expect(response).to have_http_status(:ok)
  end
end
