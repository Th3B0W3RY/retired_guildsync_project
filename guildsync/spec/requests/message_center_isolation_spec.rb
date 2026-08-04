# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Message center isolation", type: :request do
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

  let(:owner_a) do
    u = create(:user, :discord_auth)
    u.subscribe_to_plan!(basic_plan)
    u
  end

  let(:guild_a) { create(:guild, owner: owner_a) }

  let(:alice) do
    u = create(:user, :discord_auth)
    u.subscribe_to_plan!(basic_plan)
    u
  end

  let!(:alice_membership) do
    create(:guild_member, guild: guild_a, user: alice, status: :active, discord_role_id: "slot-a")
  end

  let(:outsider) do
    u = create(:user, :discord_auth)
    u.subscribe_to_plan!(basic_plan)
    u
  end

  let(:bob_no_mc) do
    u = create(:user, :discord_auth)
    u.subscribe_to_plan!(basic_plan)
    u
  end

  let!(:bob_membership) do
    create(:guild_member, guild: guild_a, user: bob_no_mc, status: :active, discord_role_id: "slot-b")
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    guild_a.update!(
      permission_role_1_id: "slot-a",
      role_1_can_use_message_center: true,
      permission_role_2_id: "slot-b",
      role_2_can_use_message_center: false
    )
    discord_double = instance_double(DiscordService, send_dm: true)
    allow(DiscordService).to receive(:new).and_return(discord_double)
  end

  it "denies users who are not guild members" do
    sign_in outsider
    get guild_message_center_path(guild_a)
    expect(response).to redirect_to(my_guilds_path)
    expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
  end

  it "denies members without message-center permission on their Discord slot" do
    sign_in bob_no_mc
    get guild_message_center_path(guild_a)
    expect(response).to redirect_to(guild_path(guild_a))
    expect(flash[:alert]).to eq(I18n.t("message_center.access_denied"))
  end

  it "allows a member when their slot has can_use_message_center" do
    sign_in alice
    get guild_message_center_path(guild_a)
    expect(response).to have_http_status(:ok)
  end

  describe "GET /guilds/:id/message_center support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    before { sign_in alice }

    it "includes default support URL in HTML" do
      get guild_message_center_path(guild_a)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_message_center_path(guild_a), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://message-center-support.example/help")
      get guild_message_center_path(guild_a)
      expect(response.body).to include("https://message-center-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://message-center-support.example/help")
      get guild_message_center_path(guild_a), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://message-center-support.example/help")
    end
  end

  it "rejects send when the recipient is not allowed (outsider)" do
    sign_in alice
    post guild_message_center_send_path(guild_a),
      params: { recipient_id: outsider.id, content: "Hello" },
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    json = JSON.parse(response.body)
    expect(json["error"]).to eq(I18n.t("message_center.invalid_recipient"))
  end

  it "rejects conversation JSON when the recipient is not allowed (outsider)" do
    sign_in alice
    get guild_message_center_conversation_path(guild_a, outsider.id),
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to eq(I18n.t("message_center.invalid_recipient"))
  end

  it "does not include DMs scoped to another guild in this guild conversation" do
    other_owner = create(:user, :discord_auth)
    other_owner.subscribe_to_plan!(basic_plan)
    guild_b = create(:guild, owner: other_owner)

    DirectMessage.create!(sender: owner_a, recipient: alice, content: "sealed to guild B", guild_id: guild_b.id)
    DirectMessage.create!(sender: owner_a, recipient: alice, content: "visible in guild A", guild_id: guild_a.id)

    sign_in owner_a
    get guild_message_center_conversation_path(guild_a, alice.id),
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    bodies = JSON.parse(response.body).map { |m| m["content"] }
    expect(bodies).to include("visible in guild A")
    expect(bodies).not_to include("sealed to guild B")
  end

  it "persists in-guild messages with this guild_id" do
    sign_in alice
    post guild_message_center_send_path(guild_a),
      params: { recipient_id: owner_a.id, content: "ping owner" },
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    msg = DirectMessage.order(:id).last
    expect(msg.guild_id).to eq(guild_a.id)
    expect(msg.sender).to eq(alice)
    expect(msg.recipient).to eq(owner_a)
  end

  it "rejects send when content is blank after sanitization" do
    sign_in alice
    post guild_message_center_send_path(guild_a),
      params: { recipient_id: owner_a.id, content: "   " },
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to eq(I18n.t("message_center.content_blank"))
    expect(DirectMessage.where(sender: alice, recipient: owner_a).count).to eq(0)
  end

  it "returns guild members from search_recipients scoped to the guild" do
    sign_in alice
    token = owner_a.username.presence || owner_a.email.split("@").first
    get guild_message_center_search_path(guild_a), params: { q: token }

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body
    expect(rows).to be_an(Array)
    owner_row = rows.find { |r| r["id"] == owner_a.id }
    expect(owner_row).to be_present
    expect(owner_row["type"]).to eq("member")
  end

  it "does not surface other guild owners in recipient search when the searcher is not the guild owner" do
    create(:guild, owner: outsider)

    sign_in alice
    q = outsider.username.presence || outsider.email.split("@").first
    get guild_message_center_search_path(guild_a), params: { q: q }

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.map { |r| r["id"] }
    expect(ids).not_to include(outsider.id)
  end
end
