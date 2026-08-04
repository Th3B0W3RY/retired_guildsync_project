# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild alliance invites (guild-scoped pending list)", type: :request do
  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:other) { create(:user, :discord_auth) }

  let(:paid_plan) do
    PricingPlan.find_or_create_by!(name: "Spec Paid Guild Alliance Invites") do |p|
      p.price = 10
      p.price_display = "$10"
      p.period = "per month"
      p.max_guilds = 5
      p.max_members_per_guild = 50
      p.active = true
      p.display_order = 97
    end
  end

  let(:paid_owner) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: paid_plan, status: :active)
    u
  end
  let(:paid_guild) { create(:guild, owner: paid_owner) }

  describe "GET /guilds/:guild_id/alliance_invites/pending" do
    it "allows the paid guild owner" do
      sign_in paid_owner
      get guild_alliance_invites_pending_path(paid_guild)
      expect(response).to have_http_status(:ok)
    end

    it "redirects a stranger (no guild access)" do
      sign_in other
      get guild_alliance_invites_pending_path(paid_guild)
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end
end
