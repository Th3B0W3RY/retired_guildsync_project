# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild members csv and tags", type: :request do
  let(:owner) { create(:user, auth_method: :discord) }
  let(:plan) { create(:pricing_plan, max_guilds: 10, max_members_per_guild: 100) }
  let!(:subscription) { create(:subscription, user: owner, pricing_plan: plan) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member_user) { create(:user, auth_method: :discord) }
  let!(:guild_member) { create(:guild_member, guild: guild, user: member_user, role: :member, status: :active) }
  let(:member_user_two) { create(:user, auth_method: :discord) }
  let!(:guild_member_two) { create(:guild_member, guild: guild, user: member_user_two, role: :member, status: :active) }

  before do
    sign_in owner
    set_mfa_verified_in_session
  end

  it "exports guild members as csv" do
    create(:user_discord_connection, user: member_user, discord_username: "raidcaptain#1234")
    get guild_members_list_path(guild, format: :csv)

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Username,Email,Role,Status,Discord Username,GuildSync Username,Tags")
    expect(response.body).to include("raidcaptain")
    expect(response.body).to include(member_user.username)
  end

  it "includes all members in CSV export even when HTML pagination params are present" do
    get guild_members_list_path(guild, format: :csv), params: { page: 1, per_page: 1 }
    expect(response).to have_http_status(:success)
    expect(response.body).to include(member_user.username)
    expect(response.body).to include(member_user_two.username)
  end

  it "renders a plain placeholder on members page" do
    get guild_members_list_path(guild)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("placeholder=\"Search user by username or Discord...\"")
    expect(response.body).not_to include("placeholder=\"<")
  end

  it "allows owner to create and assign a guild tag" do
    post guild_create_member_tag_path(guild), params: { name: "Raid Lead", color: "#ff0000" }
    tag = guild.guild_tags.find_by(name: "Raid Lead")

    expect(tag).to be_present
    post guild_assign_member_tag_path(guild, guild_member, tag)

    expect(guild_member.reload.guild_tags.pluck(:name)).to include("Raid Lead")
  end

  it "filters members by selected tag" do
    post guild_create_member_tag_path(guild), params: { name: "PvP", color: "#00ff88" }
    tag = guild.guild_tags.find_by!(name: "PvP")
    post guild_assign_member_tag_path(guild, guild_member, tag)

    get guild_members_list_path(guild), params: { tag_id: tag.id }
    expect(response).to have_http_status(:success)
    expect(response.body).to include(member_user.username)
    expect(response.body).not_to include(member_user_two.username)
  end
end
