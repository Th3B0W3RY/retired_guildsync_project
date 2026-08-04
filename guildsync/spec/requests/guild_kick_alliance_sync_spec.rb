# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild kick alliance sync", type: :request do
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
    set_mfa_verified_in_session
  end

  it "marks alliance member removed when kicked from guild" do
    delete guild_kick_member_path(guild, guild_member)

    expect(response).to redirect_to(guild_members_list_path(guild))
    expect(alliance_member.reload).to be_removed
  end
end
