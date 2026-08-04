# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance members csv and tags", type: :request do
  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:member_user) { create_alliance_paid_user!(:discord_auth) }
  let!(:guild_member) { create(:guild_member, guild: guild, user: member_user, role: :member, status: :active) }
  let!(:alliance_member) { create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active) }

  before do
    sign_in owner
  end

  it "exports alliance members as csv" do
    get alliance_alliance_members_path(alliance, format: :csv)

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Username,Email,Guild,Role,Status,Discord Username,Tags")
    expect(response.body).to include(member_user.username)
  end

  it "allows alliance leader to create and assign alliance tags" do
    post create_tag_alliance_alliance_members_path(alliance), params: { name: "Core", color: "#00ff00" }
    tag = alliance.alliance_tags.find_by(name: "Core")

    expect(tag).to be_present
    post assign_tag_alliance_alliance_members_path(alliance), params: { member_id: alliance_member.id, tag_id: tag.id }

    expect(alliance_member.reload.alliance_tags.pluck(:name)).to include("Core")
  end
end
