# frozen_string_literal: true

require "rails_helper"

# Tests that the correct, human-friendly flash/alert messages are returned
# when plan limits are reached (guild limit, member limit, OCR limit).
RSpec.describe "Plan Limit Messages", type: :request do
  # ──────────────────────────────────────────────────────────────────────────
  # Shared setup
  # ──────────────────────────────────────────────────────────────────────────
  let(:free_plan)  { PricingPlan.find_by(name: "Free") || create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 5) }
  let(:basic_plan) { create(:pricing_plan, name: "Basic", max_guilds: 5, max_members_per_guild: 25) }

  let(:user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end

  before do
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GUILD LIMIT
  # ──────────────────────────────────────────────────────────────────────────
  describe "Guild creation limit" do
    context "when the user is on the Free plan (max_guilds: 1)" do
      let!(:subscription) { create(:subscription, user: user, pricing_plan: free_plan, status: :active) }

      it "rejects guild creation and returns a clear limit-reached message" do
        # Consume the one allowed guild
        create(:guild, owner: user)

        game = create(:game, igdb_id: "999001", name: "Plan Limit Test Game #{SecureRandom.hex(4)}")
        post "/guilds", params: {
          guild: {
            name:            "Second Guild",
            description:     "Over limit",
            primary_game_id: game.id,
            game_ids:        [ game.id ]
          }
        }

        expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:unprocessable_content)
        expected = I18n.t(
          "activerecord.errors.models.guild.attributes.base.guild_limit_reached",
          plan_name: free_plan.name,
          max_guilds: free_plan.max_guilds
        )
        expect(response.body).to include(expected)
      end

      it "includes the plan name and limit in the error message" do
        # Validate the I18n message is set correctly
        message = I18n.t(
          "activerecord.errors.models.guild.attributes.base.guild_limit_reached",
          plan_name: free_plan.name,
          max_guilds: free_plan.max_guilds
        )
        expect(message).to include("limit reached")
        expect(message).to include(free_plan.name)
        expect(message).to include(free_plan.max_guilds.to_s)
      end
    end

    context "when the owner has no effective plan (current_plan is nil)" do
      let(:user) do
        u = build(:user, skip_free_plan_subscription: true)
        u.auth_method = "discord"
        u.save!
        u
      end

      it "rejects guild creation and surfaces subscription_required on the form response" do
        # User#current_plan normally auto-creates a free subscription; stub nil to exercise
        # Guild#owner_can_create_guild and the flash copy end-to-end.
        allow_any_instance_of(User).to receive(:current_plan).and_return(nil)

        game = create(:game, igdb_id: "999003", name: "No Sub Game #{SecureRandom.hex(4)}")
        post "/guilds", params: {
          guild: {
            name:            "Needs Subscription Guild",
            description:     "No plan",
            primary_game_id: game.id,
            game_ids:        [ game.id ]
          }
        }

        expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:unprocessable_content)
        expected = I18n.t("activerecord.errors.models.guild.attributes.base.subscription_required")
        expect(response.body).to include(expected)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # MEMBER LIMIT
  # ──────────────────────────────────────────────────────────────────────────
  describe "Guild member limit" do
    let!(:subscription) { create(:subscription, user: user, pricing_plan: free_plan, status: :active) }
    let!(:guild) { create(:guild, owner: user) }

    it "includes plan name and limit in the member-limit I18n message" do
      message = I18n.t(
        "activerecord.errors.models.guild_member.attributes.base.member_limit_reached",
        plan_name: free_plan.name,
        max_members: free_plan.max_members_per_guild
      )
      expect(message).to include("limit reached")
      expect(message).to include(free_plan.name)
      expect(message).to include(free_plan.max_members_per_guild.to_s)
      expect(message).to include("upgrade")
    end

    context "when accepting an invite at the owner plan member cap" do
      # Isolated plan so seeded "Free" rows (different caps) cannot mask the behavior.
      let(:capped_plan) do
        create(:pricing_plan,
               name: "MemberCap#{SecureRandom.hex(4)}",
               max_guilds: 5,
               max_members_per_guild: 5,
               price: 0,
               price_display: "$0",
               period: "month",
               active: true,
               display_order: 999)
      end
      let!(:subscription) { create(:subscription, user: user, pricing_plan: capped_plan, status: :active) }
      let!(:guild) { create(:guild, owner: user) }

      it "redirects with member_limit_reached when the guild is already full" do
        expect(guild.guild_members.active.count).to eq(1)

        4.times do |i|
          extra = create(:user, :discord_auth, skip_free_plan_subscription: true, signup_ip: "198.51.100.#{i + 20}")
          create(:subscription, user: extra, pricing_plan: capped_plan, status: :active)
          guild.guild_members.create!(user: extra, role: :member, status: :active)
        end

        expect(guild.reload.guild_members.active.count).to eq(5)

        newcomer = create(:user, :discord_auth, skip_free_plan_subscription: true, signup_ip: "198.51.100.250")
        create(:subscription, user: newcomer, pricing_plan: capped_plan, status: :active)

        sign_in user
        post guild_invite_user_path(guild), params: { user_id: newcomer.id }
        expect(response).to redirect_to(guild_members_list_path(guild))

        invite = GuildInvite.order(:id).last
        expect(invite.user_id).to eq(newcomer.id)

        sign_in newcomer
        patch accept_guild_invite_path(invite)

        expect(response).to redirect_to(dashboard_path)
        expected = I18n.t(
          "activerecord.errors.models.guild_member.attributes.base.member_limit_reached",
          plan_name: capped_plan.name,
          max_members: capped_plan.max_members_per_guild
        )
        expect(flash[:alert]).to include(expected)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # OCR MESSAGES
  # ──────────────────────────────────────────────────────────────────────────
  describe "OCR usage limit messages" do
    it "contains improved, specific limit_reached message" do
      message = I18n.t("ocr.messages.limit_reached", plan_name: "Basic", limit: 100)
      expect(message).to include("OCR requests")
      expect(message).to include("billing period")
      expect(message).to include("Basic")
      expect(message).to include("100")
    end

    it "contains improved hard_locked message" do
      message = I18n.t("ocr.messages.hard_locked")
      expect(message).to include("suspended")
      expect(message).to include("support")
    end

    it "contains improved trial_expired message" do
      message = I18n.t("ocr.messages.trial_expired")
      expect(message).to include("trial")
      expect(message).to include("plan")
    end

    it "contains improved free_blocked message" do
      message = I18n.t("ocr.messages.free_blocked")
      expect(message).to include("free")
      expect(message).to include("Subscribe")
    end

    it "contains improved ip_abuse message" do
      message = I18n.t("ocr.messages.ip_abuse")
      expect(message).to include("Unusual")
      expect(message).to include("network")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # SUBSCRIPTION REQUIRED CONCERN
  # ──────────────────────────────────────────────────────────────────────────
  describe "Subscription-required trial ended message" do
    it "contains clear next-action guidance" do
      message = I18n.t("controllers.subscription_required.trial_ended")
      expect(message).to include("trial")
      expect(message).to include("plan")
      expect(message).to include("GuildSync")
    end
  end
end
