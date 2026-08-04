# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance join plan guards", type: :request do
  let(:leader) { create(:user, :discord_auth) }
  let(:leader_guild) { create(:guild, owner: leader) }
  let(:alliance) do
    a = create(:alliance, leader_guild: leader_guild, leader_user: leader)
    create(:alliance_guild, alliance: a, guild: leader_guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: a, user: leader, guild: leader_guild, role: :gm, status: :active)
    a
  end

  let(:msg) { I18n.t("alliances.errors.join_requires_paid_plan") }

  describe "POST accept alliance invite" do
    let(:invited_owner) { create(:user, :discord_auth) }
    let(:invited_guild) { create(:guild, owner: invited_owner) }
    let!(:invite) do
      create(:alliance_invite, alliance: alliance, guild: invited_guild, invited_by_user: leader, status: :pending)
    end

    it "blocks the invited guild owner when they are on a free plan" do
      sign_in invited_owner
      post accept_alliance_alliance_invite_path(alliance, invite), params: { return_to: "guild", guild_id: invited_guild.id }
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(msg)
    end
  end

  describe "GET guild alliance join request page" do
    let(:requester_guild) { create(:guild, owner: requester) }
    let(:requester) { create(:user, :discord_auth) }

    it "redirects a free-plan owner away from the join form" do
      sign_in requester
      get new_guild_alliance_join_request_path(requester_guild)
      expect(response).to redirect_to(guild_path(requester_guild))
      expect(flash[:alert]).to eq(msg)
    end

    context "when owner has an active trial on a paid plan" do
      let(:requester) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
      let(:paid_plan) do
        create(:pricing_plan, name: "JoinTrialPaid", price: 15, price_display: "$15", period: "per month",
                              max_guilds: 5, max_members_per_guild: 50, display_order: 99, active: true)
      end

      before do
        create(:subscription, user: requester, pricing_plan: paid_plan, status: :trialing,
                              started_at: Time.current, trial_ends_at: 14.days.from_now)
      end

      it "allows the join request form" do
        sign_in requester
        get new_guild_alliance_join_request_path(requester_guild)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST alliance join request" do
    let(:requester) { create(:user, :discord_auth) }
    let(:requester_guild) { create(:guild, owner: requester) }

    before { sign_in requester }

    it "does not create a join request for a free-plan owner" do
      expect {
        post alliance_alliance_join_requests_path(alliance),
             params: { requesting_guild_id: requester_guild.id }
      }.not_to change(AllianceJoinRequest, :count)
      expect(response).to redirect_to(guild_path(requester_guild))
      expect(flash[:alert]).to eq(msg)
    end
  end
end
