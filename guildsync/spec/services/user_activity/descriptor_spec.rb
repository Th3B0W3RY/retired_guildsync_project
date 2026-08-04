# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserActivity::Descriptor do
  def build(controller_name:, action_name:, path:, label_override: nil)
    described_class.build(
      controller_name: controller_name,
      action_name: action_name,
      path: path,
      label_override: label_override
    )
  end

  describe "skipped internal endpoints" do
    it "skips OAuth verify_session round-trips" do
      %w[discord_user_auth google_user_auth microsoft_user_auth].each do |controller|
        result = build(controller_name: controller, action_name: "verify_session", path: "/auth/x/verify")
        expect(result.skip?).to be(true)
      end
    end

    it "skips dashboard polling and the activity feed itself" do
      %w[dashboard recent_activity dashboard_stats activity].each do |action|
        result = build(controller_name: "home", action_name: action, path: "/dashboard/#{action}")
        expect(result.skip?).to be(true)
      end
    end

    it "skips the login form and session create/destroy" do
      %w[new create destroy].each do |action|
        result = build(controller_name: "sessions", action_name: action, path: "/login")
        expect(result.skip?).to be(true)
      end
    end
  end

  describe "sign-in entries" do
    it "labels a Discord callback as a friendly sign-in with no link" do
      result = build(controller_name: "discord_user_auth", action_name: "callback", path: "/auth/discord/callback")
      expect(result.skip?).to be(false)
      expect(result.label).to eq(I18n.t("user_activity.signed_in_discord"))
      expect(result.link_path).to be_nil
      expect(result.linkable?).to be(false)
    end

    it "labels a Microsoft callback as the Outlook sign-in copy" do
      result = build(controller_name: "microsoft_user_auth", action_name: "callback", path: "/auth/microsoft/callback")
      expect(result.label).to eq(I18n.t("user_activity.signed_in_microsoft"))
      expect(result.link_path).to be_nil
    end

    it "never leaks the controller or action name in the label" do
      result = build(controller_name: "discord_user_auth", action_name: "callback", path: "/auth/discord/callback")
      expect(result.label).not_to include("Discord user auth")
      expect(result.label).not_to include("Callback")
    end
  end

  describe "ordinary pages" do
    it "records a linkable entry with a humanized page name" do
      result = build(controller_name: "member_dashboard", action_name: "index", path: "/member/dashboard")
      expect(result.skip?).to be(false)
      expect(result.label).to eq("Member dashboard")
      expect(result.link_path).to eq("/member/dashboard")
      expect(result.linkable?).to be(true)
    end

    it "prefers a controller-provided label override" do
      result = build(
        controller_name: "guilds",
        action_name: "show",
        path: "/guilds/1",
        label_override: "Members – Knights"
      )
      expect(result.label).to eq("Members – Knights")
      expect(result.link_path).to eq("/guilds/1")
    end

    it "never includes the action name in the fallback label" do
      result = build(controller_name: "billing", action_name: "show", path: "/billing")
      expect(result.label).to eq("Billing")
      expect(result.label).not_to include("–")
    end

    it "does not link pages under /auth even if recorded" do
      result = build(controller_name: "discord_user_auth", action_name: "callback", path: "/auth/discord/callback")
      expect(result.link_path).to be_nil
    end
  end
end
