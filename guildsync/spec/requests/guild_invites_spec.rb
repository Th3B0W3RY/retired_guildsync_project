# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Guild Invites", type: :request do
  include_context "Discord API stubs"

  before do
    # Stub Stripe API calls using WebMock with unique customer IDs
    @stripe_customer_counter ||= 0
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return do |request|
        @stripe_customer_counter += 1
        {
          status: 200,
          body: { id: "cus_test#{@stripe_customer_counter}", email: "test@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end
  end

  let(:owner) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10, max_members_per_guild: 100) }
  let!(:owner_subscription) { create(:subscription, user: owner, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: owner) }
  let(:discord_guild_id) { "123456789012345678" }
  let!(:discord_setting) do
    create(:guild_discord_setting,
           guild: guild,
           discord_guild_id: discord_guild_id,
           connected_at: Time.current)
  end

  let(:invited_user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end

  let(:default_role) { create(:discord_role_sync, guild: guild, role_id: "default_role_id", role_name: "Member") }

  before do
    sign_in owner
    set_mfa_verified_in_session

    # Stub Discord DM creation
    stub_request(:post, "https://discord.com/api/v10/users/@me/channels")
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(
        status: 200,
        body: { id: "dm_channel_id" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub Discord DM message sending
    stub_request(:post, "https://discord.com/api/v10/channels/dm_channel_id/messages")
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(status: 200, body: {}.to_json)

    # Stub getting guild member
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/.+})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(
        status: 200,
        body: {
          user: { id: "discord_user_id", username: "testuser" },
          roles: []
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub adding role to member
    stub_request(:put, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/.+/roles/.+})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(status: 204)
  end

  describe "POST /guilds/:id/invite_user" do
    context "with Discord connected user" do
      let!(:user_discord_connection) do
        create(:user_discord_connection, user: invited_user, discord_user_id: "discord_user_id")
      end

      it "creates an invite and sends Discord DM" do
        expect {
          post guild_invite_user_path(guild), params: { user_id: invited_user.id }
        }.to change { GuildInvite.count }.by(1)

        invite = GuildInvite.last
        expect(invite.user).to eq(invited_user)
        expect(invite.guild).to eq(guild)
        expect(invite.invited_by).to eq(owner)
        expect(invite.status).to eq("pending")

        # Verify Discord DM was sent
        expect(WebMock).to have_requested(:post, "https://discord.com/api/v10/users/@me/channels")
        expect(WebMock).to have_requested(:post, "https://discord.com/api/v10/channels/dm_channel_id/messages")
          .with(body: hash_including(content: /invited to/))

        expect(response).to redirect_to(guild_members_list_path(guild))
        expect(flash[:notice]).to include("invited successfully")
      end
    end

    context "without Discord connected user" do
      it "creates an invite without sending Discord DM" do
        expect {
          post guild_invite_user_path(guild), params: { user_id: invited_user.id }
        }.to change { GuildInvite.count }.by(1)

        # Should not attempt Discord DM
        expect(WebMock).not_to have_requested(:post, "https://discord.com/api/v10/users/@me/channels")

        expect(response).to redirect_to(guild_members_list_path(guild))
        expect(flash[:notice]).to include("invited successfully")
      end
    end

    it "prevents inviting user who is already a member" do
      create(:guild_member, guild: guild, user: invited_user)

      expect {
        post guild_invite_user_path(guild), params: { user_id: invited_user.id }
      }.not_to change { GuildInvite.count }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("Silly goose")
    end

    it "prevents duplicate pending invites" do
      create(:guild_invite, guild: guild, user: invited_user, invited_by: owner, status: :pending)

      expect {
        post guild_invite_user_path(guild), params: { user_id: invited_user.id }
      }.not_to change { GuildInvite.count }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("already been invited")
    end

    it "denies invite when the current user cannot manage roles" do
      peon = create(:user)
      peon.update!(auth_method: "discord")
      create(:guild_member, guild: guild, user: peon, role: :member, status: :active)

      sign_in peon
      set_mfa_verified_in_session

      expect {
        post guild_invite_user_path(guild), params: { user_id: invited_user.id }
      }.not_to change { GuildInvite.count }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.invite_denied"))
    end

    it "redirects when user_id does not match any user" do
      missing_id = User.maximum(:id).to_i + 99_999

      expect {
        post guild_invite_user_path(guild), params: { user_id: missing_id }
      }.not_to change { GuildInvite.count }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.invite.user_not_found"))
    end
  end

  describe "PATCH /guild_invites/:id/accept" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner, status: :pending) }
    let!(:user_discord_connection) do
      create(:user_discord_connection, user: invited_user, discord_user_id: "discord_user_id")
    end

    before do
      # Ensure invited_user is not already a member (guild factory creates owner as member)
      GuildMember.where(guild: guild, user: invited_user).destroy_all
      sign_in invited_user
      set_mfa_verified_in_session
    end

    context "with default role set" do
      before do
        guild.update!(default_role_id: default_role.role_id)
        # Ensure invited_user is not already a member
        guild.guild_members.where(user: invited_user).destroy_all
      end

      it "adds user to guild and applies default Discord role" do
        expect {
          patch accept_guild_invite_path(invite)
        }.to change { guild.guild_members.count }.by(1)
          .and change { invite.reload.status }.from("pending").to("accepted")

        member = guild.guild_members.find_by(user: invited_user)
        expect(member).to be_present
        expect(member.role).to eq("member")
        expect(member.discord_role_id).to eq(default_role.role_id)

        # Verify Discord role was added
        expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_id/roles/#{default_role.role_id}")

        expect(response).to redirect_to(guild_path(guild))
        expect(flash[:notice]).to include("Welcome")
      end
    end

    context "without default role set" do
      before do
        # Ensure invited_user is not already a member (guild factory creates owner as member)
        GuildMember.where(guild: guild, user: invited_user).destroy_all
      end

      it "adds user to guild without Discord role" do
        expect {
          patch accept_guild_invite_path(invite)
        }.to change { guild.guild_members.count }.by(1)
        
        invite.reload
        expect(invite.status).to eq("accepted")

        member = guild.guild_members.find_by(user: invited_user)
        expect(member).to be_present
        expect(member.role).to eq("member")
        expect(member.discord_role_id).to be_nil

        # Should not attempt to add Discord role
        expect(WebMock).not_to have_requested(:put, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/.+/roles/.+})

        expect(response).to redirect_to(guild_path(guild))
        expect(flash[:notice]).to include("Welcome")
      end
    end

    it "prevents accepting invite for wrong user" do
      other_user = create(:user)
      other_user.update!(auth_method: "discord")
      sign_in other_user
      set_mfa_verified_in_session

      expect {
        patch accept_guild_invite_path(invite)
      }.not_to change { guild.guild_members.count }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "PATCH /guild_invites/:id/deny" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner, status: :pending) }
    let!(:owner_discord_connection) do
      create(:user_discord_connection, user: owner, discord_user_id: "owner_discord_id")
    end

    before do
      sign_in invited_user
      set_mfa_verified_in_session

      # Stub DM channel for owner
      stub_request(:post, "https://discord.com/api/v10/users/@me/channels")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: { id: "owner_dm_channel_id" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:post, "https://discord.com/api/v10/channels/owner_dm_channel_id/messages")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(status: 200, body: {}.to_json)
    end

    it "denies invite and notifies guild owner via Discord" do
      initial_count = guild.guild_members.count
      expect {
        patch deny_guild_invite_path(invite)
      }.to change { invite.reload.status }.from("pending").to("denied")
      
      expect(guild.guild_members.count).to eq(initial_count)

      # Verify owner was notified via Discord
      expect(WebMock).to have_requested(:post, "https://discord.com/api/v10/users/@me/channels")
      expect(WebMock).to have_requested(:post, "https://discord.com/api/v10/channels/owner_dm_channel_id/messages")
        .with(body: hash_including(content: /denied your invite/))

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:notice]).to include("declined")
    end

    it "prevents denying invite for wrong user" do
      other_user = create(:user)
      other_user.update!(auth_method: "discord")
      sign_in other_user
      set_mfa_verified_in_session

      expect {
        patch deny_guild_invite_path(invite)
      }.not_to change { invite.reload.status }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "PATCH /guild_invites/:id/dismiss" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner, status: :pending) }

    it "allows the guild owner to dismiss a pending invite" do
      sign_in owner
      set_mfa_verified_in_session

      patch dismiss_guild_invite_path(invite)
      expect(response).to redirect_to(guild_review_applications_path(guild))
      expect(flash[:notice]).to include("dismissed")
      expect(invite.reload.dismissed).to be true
    end

    it "redirects a stranger without access to the invite" do
      stranger = create(:user)
      stranger.update!(auth_method: "discord")
      sign_in stranger
      set_mfa_verified_in_session

      patch dismiss_guild_invite_path(invite)
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
      expect(invite.reload.dismissed).to be_falsey
    end
  end

  describe "GET /guilds/:id/users/search" do
    let!(:user1) { create(:user, username: "testuser1", email: "test1@example.com") }
    let!(:user2) { create(:user, username: "testuser2", email: "test2@example.com") }
    let!(:discord_user) do
      u = create(:user, username: "discorduser", email: "discord@example.com")
      create(:user_discord_connection, user: u, discord_username: "DiscordUser#1234")
      u
    end

    it "searches users by username" do
      get guild_search_users_path(guild), params: { q: "testuser1" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["users"].length).to eq(1)
      expect(json["users"].first["username"]).to eq("testuser1")
    end

    it "searches users by Discord username" do
      get guild_search_users_path(guild), params: { q: "DiscordUser" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["users"].length).to eq(1)
      expect(json["users"].first["username"]).to eq("discorduser")
      expect(json["users"].first["discord_username"]).to eq("DiscordUser#1234")
    end

    it "returns empty users for queries less than 1 character" do
      get guild_search_users_path(guild), params: { q: "" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["users"]).to eq([])
      expect(json["pagination"]["total_count"]).to eq(0)
    end

    it "paginates users with page and per_page" do
      5.times do |i|
        create(:user, username: "pagineo#{i}", email: "pagineo#{i}@example.com")
      end

      get guild_search_users_path(guild), params: { q: "pagineo", page: 1, per_page: 3 }
      json = JSON.parse(response.body)
      expect(json["users"].length).to eq(3)
      expect(json["pagination"]).to include(
        "page" => 1,
        "per_page" => 3,
        "total_count" => 5,
        "total_pages" => 2
      )

      get guild_search_users_path(guild), params: { q: "pagineo", page: 2, per_page: 3 }
      json2 = JSON.parse(response.body)
      expect(json2["users"].length).to eq(2)
      expect(json2["pagination"]["page"]).to eq(2)
    end
  end
end

