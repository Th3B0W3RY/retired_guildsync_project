# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Join links", type: :request do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member_user) { create(:user, :with_mfa) }

  # Bypass MFA/auth filters so we can test join-specific logic
  before do
    allow_any_instance_of(ApplicationController).to receive(:require_mfa_if_enabled).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:ensure_fully_authenticated).and_return(true)
  end

  # =========================================================================
  # GET /join/:token (show)
  # =========================================================================
  describe "GET /join/:token" do
    it "renders show for a valid, non-expired link" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)
      get join_guild_path(invite.token)
      expect(response).to have_http_status(:ok)
      # Prove the join landing (not only layout chrome): title, CTA, guild name, one-time hint.
      expect(response.body).to include(I18n.t("join.title"))
      expect(response.body).to include(I18n.t("join.cta"))
      expect(response.body).to include(I18n.t("join.one_time_hint"))
      expect(response.body).to include(guild.name)
    end

    it "renders show when expires_at is nil (link does not expire by time)" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: nil)
      get join_guild_path(invite.token)
      expect(response).to have_http_status(:ok)
      expect(GuildInviteLink.find_by(id: invite.id)).to be_present
    end

    it "rejects expired links and removes them" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.day.ago)
      get join_guild_path(invite.token)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t("join.invalid_title"))
      expect(GuildInviteLink.find_by(id: invite.id)).to be_nil
    end

    it "returns not found for an invalid token" do
      get join_guild_path("nonexistent-token-xyz")
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t("join.invalid_title"))
    end

    it "redirects signed-in users to complete" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)
      sign_in member_user
      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(true)

      get join_guild_path(invite.token)
      expect(response).to redirect_to(join_complete_path)
    end
  end

  # =========================================================================
  # GET /join/complete
  # =========================================================================
  describe "GET /join/complete" do
    before { sign_in member_user }

    it "adds the user to the guild and destroys the link" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)

      # Set the session token via the show action
      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(false)
      get join_guild_path(invite.token)

      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(true)
      get join_complete_path

      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:notice]).to eq(I18n.t("join.welcome", name: guild.name))
      expect(guild.guild_members.exists?(user: member_user)).to be true
      expect(GuildInviteLink.find_by(id: invite.id)).to be_nil
    end

    it "rejects expired links from session token" do
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 10.minutes.from_now)
      get join_guild_path(invite.token)

      invite.update!(expires_at: 1.minute.ago)
      get join_complete_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("join.invalid_or_used"))
      expect(GuildInviteLink.find_by(id: invite.id)).to be_nil
    end

    it "redirects with notice when user is already a member" do
      guild.guild_members.create!(user: member_user, role: :member, status: :active)
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)

      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(false)
      get join_guild_path(invite.token)

      get join_complete_path

      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:notice]).to eq(I18n.t("join.already_member", name: guild.name))
      expect(GuildInviteLink.find_by(id: invite.id)).to be_nil
    end

    it "redirects to dashboard when no session token exists" do
      get join_complete_path
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("join.invalid_or_used"))
    end

    it "blocks join when IP policy detects multi-account conflict" do
      conflicting_user = create(:user, signup_ip: "203.0.113.44")
      member_user.update!(signup_ip: "203.0.113.44")
      other_guild = create(:guild)
      create(:guild_member, user: conflicting_user, guild: other_guild, status: :active)
      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)

      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(false)
      get join_guild_path(invite.token)

      get join_complete_path

      expect(response).to redirect_to(dashboard_path)
      expect(guild.guild_members.exists?(user: member_user)).to be(false)
      expect(flash[:alert]).to eq(I18n.t("compliance.ip_conflict.warning_message"))
    end

    it "blocks join when the user is already in another alliance" do
      target_alliance = create(:alliance, leader_guild: guild, leader_user: owner)
      create(:alliance_guild, alliance: target_alliance, guild: guild, status: :active, joined_at: Time.current)

      home = create(:guild, owner: member_user)
      other_alliance = create(:alliance, leader_guild: home, leader_user: member_user)
      create(:alliance_guild, alliance: other_alliance, guild: home, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: other_alliance, user: member_user, guild: home, role: :gm, status: :active)

      invite = guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now)
      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(false)
      get join_guild_path(invite.token)
      allow_any_instance_of(JoinController).to receive(:mfa_verified_for_session?).and_return(true)
      get join_complete_path

      expect(response).to redirect_to(dashboard_path)
      expect(guild.guild_members.exists?(user: member_user)).to be(false)
      expect(flash[:alert]).to eq(I18n.t("join.conflicting_alliance"))
    end
  end
end
