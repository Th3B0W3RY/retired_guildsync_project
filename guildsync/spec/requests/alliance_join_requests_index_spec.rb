# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance join requests index", type: :request do
  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end

  before { sign_in owner }

  it "GET index lists pending requests for a manager" do
    g2 = create(:guild, owner: create(:user, :discord_auth))
    create(:alliance_join_request,
           alliance: alliance,
           requesting_guild: g2,
           requested_by_user: g2.owner,
           status: :pending)

    get alliance_alliance_join_requests_path(alliance)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(g2.name)
  end
end
