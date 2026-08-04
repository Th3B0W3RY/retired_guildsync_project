# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:user) { create(:user) }

  describe "#current_plan" do
    it "returns the pricing plan tied to the current subscription" do
      plan = user.current_plan

      expect(plan).to be_present
      expect(plan.name).to eq("Free")
      expect(user.current_subscription.pricing_plan).to eq(plan)
    end

    it "creates a subscription when one does not exist" do
      user.subscriptions.delete_all

      expect(user.current_plan).to eq(free_plan)
      expect(user.current_subscription).to be_present
    end
  end

  describe "#blocked_from_alliance_features? / #blocked_from_alliance_join?" do
    it "is true on the default free plan" do
      expect(user.blocked_from_alliance_features?).to be true
      expect(user.blocked_from_alliance_join?).to be true
    end

    it "is false while on an active trial for a non-free paid plan" do
      paid = create(:pricing_plan, name: "TrialBlockPlan", price: 12, price_display: "$12", period: "per month",
                                    max_guilds: 5, max_members_per_guild: 50, display_order: 42, active: true)
      user.subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: paid, status: :trialing, started_at: Time.current,
                            trial_ends_at: 7.days.from_now)
      user.reload
      expect(user.blocked_from_alliance_features?).to be false
      expect(user.blocked_from_alliance_join?).to be false
    end

    it "is true when trial on a paid plan has expired (no access)" do
      paid = create(:pricing_plan, name: "TrialExpiredPlan", price: 12, price_display: "$12", period: "per month",
                                    max_guilds: 5, max_members_per_guild: 50, display_order: 44, active: true)
      user.subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: paid, status: :trialing, started_at: 2.weeks.ago,
                            trial_ends_at: 1.day.ago)
      user.reload
      expect(user.trial_active?).to be false
      expect(user.blocked_from_alliance_features?).to be true
      expect(user.blocked_from_alliance_join?).to be true
    end

    it "is false on a non-free paid active subscription" do
      paid = create(:pricing_plan, name: "JoinOkPlan", price: 12, price_display: "$12", period: "per month",
                                   max_guilds: 5, max_members_per_guild: 50, display_order: 43, active: true)
      user.subscribe_to_plan!(paid)
      user.reload
      expect(user.blocked_from_alliance_features?).to be false
      expect(user.blocked_from_alliance_join?).to be false
    end
  end

  it "defines a 14-day standard trial length" do
    expect(User::STANDARD_TRIAL_PERIOD_DAYS).to eq(14)
  end

  describe "#has_used_trial?" do
    let(:basic) do
      create(:pricing_plan, name: "Basic", price: 12, price_display: "$12", period: "per month",
                            max_guilds: 2, max_members_per_guild: 50, display_order: 10, active: true)
    end

    it "is false during an active trial" do
      user.subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: basic, status: :trialing, started_at: Time.current,
                            trial_ends_at: 5.days.from_now)
      user.reload
      expect(user.has_used_trial?).to be false
    end

    it "is true when trial_ends_at is in the past" do
      user.subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: basic, status: :canceled, canceled_at: 1.day.ago,
                            trial_ends_at: 2.days.ago)
      user.reload
      expect(user.has_used_trial?).to be true
    end

    it "is true when the user canceled during an unexpired trial window" do
      user.subscriptions.where(status: :active).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: basic, status: :canceled, canceled_at: Time.current,
                            trial_ends_at: 5.days.from_now)
      user.reload
      expect(user.has_used_trial?).to be true
    end
  end

  describe "#can_create_guild?" do
    let(:limited_plan) { create(:pricing_plan, name: "Pro", max_guilds: 2) }

    before do
      user.subscribe_to_plan!(limited_plan)
    end

    it "returns true when owned guilds are below the plan limit" do
      create(:guild, owner: user)

      expect(user.can_create_guild?).to be true
    end

    it "returns false when owned guilds meet the plan limit" do
      create_list(:guild, limited_plan.max_guilds, owner: user)

      expect(user.can_create_guild?).to be false
    end

    it "ignores archived guilds for plan-limit counting" do
      create(:guild, owner: user, archived_at: 2.days.ago, scheduled_purge_at: 1.year.from_now)

      expect(user.can_create_guild?).to be true
    end
  end

  describe "#can_add_member_to_guild?" do
    let(:limited_plan) { create(:pricing_plan, name: "Team", max_members_per_guild: 2) }
    let(:guild) { create(:guild, owner: user) }

    before do
      user.subscribe_to_plan!(limited_plan)
    end

    it "returns true when member count is below the plan limit" do
      # Owner is already a member (created by factory), so with limit of 2, we have 1 member
      # We should be able to add 1 more (total would be 2, which is at the limit but not over)
      # Actually, the check is < not <=, so with limit 2, we can have 0 or 1 members
      # Since owner is already 1, we're at capacity. Let's increase the limit for this test.
      limited_plan.update!(max_members_per_guild: 3)

      # Now with limit 3, owner is 1, we can add 1 more (total 2, which is < 3)
      create(:guild_member, guild: guild, user: create(:user))

      expect(user.can_add_member_to_guild?(guild)).to be true
    end

    it "returns false when member count meets the plan limit" do
      # Owner is already a member, so we need to add (limit - 1) more members
      (limited_plan.max_members_per_guild - 1).times do
        create(:guild_member, guild: guild, user: create(:user))
      end

      expect(user.can_add_member_to_guild?(guild)).to be false
    end
  end

  describe "#generate_otp_secret_if_needed" do
    it "creates an otp_secret when missing" do
      user.update!(otp_secret: nil)

      user.generate_otp_secret_if_needed

      expect(user.otp_secret).to be_present
    end

    it "does not change an existing otp_secret" do
      original_secret = user.otp_secret

      user.generate_otp_secret_if_needed

      expect(user.otp_secret).to eq(original_secret)
    end
  end

  describe "#has_valid_discord_connection?" do
    it "returns false when no Discord connection exists" do
      expect(user.has_valid_discord_connection?).to be false
    end

    it "returns true when the user has a Discord connection with an access token" do
      create(:user_discord_connection, user: user, discord_user_id: "123456789", access_token: "abc123")

      expect(user.has_valid_discord_connection?).to be true
    end
  end

  describe "subscription and trial management" do
    let!(:basic_trial_plan) do
      create(:pricing_plan,
             name: "Basic",
             price: 9.99,
             price_display: "$9.99",
             period: "month",
             max_guilds: 5,
             max_members_per_guild: 50,
             active: true,
             display_order: 2)
    end

    let!(:premium_plan) do
      create(:pricing_plan,
             name: "Premium",
             price: 19.99,
             price_display: "$19.99",
             period: "month",
             max_guilds: nil,
             max_members_per_guild: nil,
             active: true,
             display_order: 3)
    end

    describe "#access_allowed?" do
      it "allows access with free plan" do
        expect(user.access_allowed?).to be true
      end
    end

    describe "trial management" do
      it "allows starting a trial for Basic" do
        expect(user.can_start_trial?).to be true

        user.start_trial_from_free!(basic_trial_plan)
        user.reload # Reload to get fresh subscription data
        expect(user.current_subscription.status).to eq("trialing")
        expect(user.current_subscription.trial_ends_at).to be_present
        expect(user.current_subscription.trial_ends_at).to be > Time.current
        expect(user.trial_active?).to be true
      end

      it "prevents starting multiple trials" do
        user.start_trial_from_free!(basic_trial_plan)
        user.reload
        expect(user.can_start_trial?).to be false
        expect { user.start_trial_from_free!(basic_trial_plan) }.to raise_error(ArgumentError, /trial/i)
      end

      it "allows switching plans during trial" do
        user.start_trial_from_free!(basic_trial_plan)
        user.reload
        original_trial_end = user.current_subscription.trial_ends_at

        user.switch_plan_during_trial!(free_plan)
        user.reload
        expect(user.current_plan).to eq(free_plan)
        expect(user.current_subscription.trial_ends_at).to eq(original_trial_end)
      end

      it "prevents starting trial for free plan" do
        expect {
          user.start_trial_from_free!(free_plan)
        }.to raise_error(ArgumentError, /Cannot start trial for Free plan/)
      end
    end

    describe "plan limits" do
      it "allows unlimited guilds for premium plan" do
        user.subscribe_to_plan!(premium_plan)
        expect(user.current_plan.unlimited_guilds?).to be true
        expect(user.can_create_guild?).to be true

        # Create multiple guilds
        10.times { create(:guild, owner: user) }
        expect(user.can_create_guild?).to be true
      end
    end

    describe "validations" do
      it "validates username format" do
        user = build(:user, username: "invalid-username!")
        expect(user).not_to be_valid
        expect(user.errors[:username]).to be_present
      end

      it "validates username length" do
        user = build(:user, username: "ab")
        expect(user).not_to be_valid

        user = build(:user, username: "a" * 31)
        expect(user).not_to be_valid
      end

      it "validates email uniqueness" do
        existing_user = create(:user, email: "test@example.com")
        new_user = build(:user, email: "test@example.com")
        expect(new_user).not_to be_valid
      end

      it "requires a stronger password with letters and numbers" do
        user = build(:user, password: "abcdefghij", password_confirmation: "abcdefghij")
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include at least one letter and one number")
      end

      it "rejects passwords containing spaces" do
        user = build(:user, password: "password 123", password_confirmation: "password 123")
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("cannot contain spaces")
      end

      it "requires at least ten characters for passwords" do
        user = build(:user, password: "abc123", password_confirmation: "abc123")
        expect(user).not_to be_valid
        expect(user.errors[:password]).to be_present
      end
    end

    describe "associations" do
      it "has correct associations" do
        guild = create(:guild, owner: user)
        event = create(:event, guild: guild, created_by: user)

        expect(user.owned_guilds).to include(guild)
        expect(user.created_events).to include(event)
        expect(user.guilds).to include(guild)
      end
    end
  end

  describe "cascade deletions" do
    let(:user) { create(:user) }
    let(:guild) { create(:guild, owner: user) }
    let!(:event) { create(:event, guild: guild, created_by: user) }
    let!(:subscription) { user.current_subscription }

    it "deletes associated records when user is deleted" do
      user_id = user.id
      expect(Guild.where(owner_id: user_id).count).to eq(1)
      expect(Event.where(created_by_id: user_id).count).to eq(1)
      expect(Subscription.where(user_id: user_id).count).to eq(1)

      user.destroy

      expect(Guild.where(owner_id: user_id).count).to eq(0)
      expect(Event.where(created_by_id: user_id).count).to eq(0)
      expect(Subscription.where(user_id: user_id).count).to eq(0)
    end
  end

  describe "one_account_per_signup_ip" do
    it "allows first user from an IP" do
      skip "No signup_ip column" unless User.column_names.include?("signup_ip")
      u = build(:user, email: "first@example.com", username: "firstuser", signup_ip: "192.168.1.1")
      expect(u).to be_valid
    end

    it "rejects second user from same IP" do
      skip "No signup_ip column" unless User.column_names.include?("signup_ip")
      create(:user, email: "existing@example.com", username: "existinguser", signup_ip: "10.0.0.1")
      second = build(:user, email: "second@example.com", username: "seconduser", signup_ip: "10.0.0.1")
      expect(second).not_to be_valid
      expect(second.errors[:base]).to include(I18n.t("errors.attributes.user.one_account_per_ip"))
    end

    it "allows multiple users from loopback in test (API integration / Playwright share one client IP)" do
      skip "No signup_ip column" unless User.column_names.include?("signup_ip")
      create(:user, email: "loop1@example.com", username: "loopuser1", signup_ip: "127.0.0.1")
      second = build(:user, email: "loop2@example.com", username: "loopuser2", signup_ip: "127.0.0.1")
      expect(second).to be_valid
    end
  end

  describe "#name_for_discord_embed" do
    it "prefers discord_global_name over username and discord_username" do
      u = build(:user,
                username: "siteslug",
                discord_username: "discord_handle",
                discord_global_name: "Friendly Name",
                email: "embed_test@example.com")
      expect(u.name_for_discord_embed).to eq("Friendly Name")
    end

    it "uses site username before Discord login handle when global name is blank" do
      u = build(:user,
                username: "siteuser",
                discord_username: "discordname",
                discord_global_name: nil,
                email: "embed_test2@example.com")
      expect(u.name_for_discord_embed).to eq("siteuser")
    end
  end

  describe "#discord_display_name_for_guild_application" do
    it "returns nil when Discord is not connected" do
      u = create(:user, discord_global_name: "Should Not Show", discord_username: "u")
      expect(u.discord_display_name_for_guild_application).to be_nil
    end

    it "prefers discord_global_name over connection and legacy username" do
      u = create(:user, discord_global_name: "Display Name", discord_username: "legacy#1234")
      create(:user_discord_connection, user: u, discord_username: "api_login")
      expect(u.discord_display_name_for_guild_application).to eq("Display Name")
    end

    it "uses connection discord_username when global name is blank" do
      u = create(:user, discord_global_name: nil, discord_username: "legacy#1234")
      create(:user_discord_connection, user: u, discord_username: "api_login")
      expect(u.discord_display_name_for_guild_application).to eq("api_login")
    end

    it "falls back to user discord_username when connection handle is blank" do
      u = create(:user, discord_global_name: nil, discord_username: "olduser#9999")
      create(:user_discord_connection, user: u, discord_username: "")
      expect(u.discord_display_name_for_guild_application).to eq("olduser#9999")
    end
  end

  describe "UserDeviseMailDelivery (Devise emails)" do
    include ActiveJob::TestHelper

    it "queues MailDeliveryJob for reset_password_instructions" do
      u = create(:user, skip_free_plan_subscription: true)
      expect {
        u.send(:send_devise_notification, :reset_password_instructions, "rawtoken", {})
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "queues MailDeliveryJob for password_change" do
      u = create(:user, skip_free_plan_subscription: true)
      expect {
        u.send(:send_devise_notification, :password_change)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "queues MailDeliveryJob for email_changed with recipient hash (Devise calling convention)" do
      u = create(:user, skip_free_plan_subscription: true)
      expect {
        u.send(:send_devise_notification, :email_changed, { to: "previous@example.com" })
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "does not expose send_devise_notification as a public instance method" do
      u = create(:user, skip_free_plan_subscription: true)
      expect((u.public_methods & [ :send_devise_notification ])).to be_empty
    end
  end
end
