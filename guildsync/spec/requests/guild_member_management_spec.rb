# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Guild Member Management", type: :request do
  include_context "Discord API stubs"

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

  let(:member1) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:member2) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:member3) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end

  let(:role1) { create(:discord_role_sync, guild: guild, role_id: "role1_id", role_name: "Leader") }
  let(:role2) { create(:discord_role_sync, guild: guild, role_id: "role2_id", role_name: "Officer") }
  let(:role3) { create(:discord_role_sync, guild: guild, role_id: "role3_id", role_name: "Member") }

  before do
    sign_in owner
    set_mfa_verified_in_session

    # Create members
    @guild_member1 = create(:guild_member, guild: guild, user: member1, role: :member)
    @guild_member2 = create(:guild_member, guild: guild, user: member2, role: :member)
    @guild_member3 = create(:guild_member, guild: guild, user: member3, role: :admin)

    # Create Discord connections for members
    create(:user_discord_connection, user: member1, discord_user_id: "discord_user_1")
    create(:user_discord_connection, user: member2, discord_user_id: "discord_user_2")
    create(:user_discord_connection, user: member3, discord_user_id: "discord_user_3")

    # Stub Discord API calls for getting guild member
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_\d+})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return do |request|
        user_id = request.uri.path.split('/').last
        {
          status: 200,
          body: {
            user: { id: user_id, username: "testuser" },
            roles: user_id == "discord_user_1" ? [role1.role_id] : []
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end

    # Stub Discord role assignment
    stub_request(:put, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_\d+/roles/.+})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(status: 204)

    # Stub Discord role removal
    stub_request(:delete, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_\d+/roles/.+})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(status: 204)

    # Stub getting guild roles
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/roles})
      .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
      .to_return(
        status: 200,
        body: [
          { id: role1.role_id, name: role1.role_name, position: 30 },
          { id: role2.role_id, name: role2.role_name, position: 20 },
          { id: role3.role_id, name: role3.role_name, position: 10 }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub loading guild channels on settings page.
    stub_request(:get, "https://discord.com/api/v10/guilds/#{discord_guild_id}/channels")
      .with(headers: { "Authorization" => /^Bot .+/ })
      .to_return(
        status: 200,
        body: [
          { id: "events_chan_1", name: "events", type: 0 },
          { id: "polls_chan_1", name: "polls", type: 0 }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "GET /guilds/:id/members" do
    it "renders tag filter labels from i18n" do
      get guild_members_list_path(guild)
      expect(response.body).to include(I18n.t("guilds.members.tags.filter_label"))
      expect(response.body).to include(I18n.t("guilds.members.tags.filter_all"))
      expect(response.body).to include(I18n.t("guilds.members.tags.filter_untagged"))
    end

    it "renders clear tag filter link when a tag filter is active" do
      get guild_members_list_path(guild), params: { tag_id: "untagged" }
      expect(response.body).to include(I18n.t("guilds.members.tags.clear_filter"))
    end

    it "displays members list" do
      get guild_members_list_path(guild)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(member1.username)
      expect(response.body).to include(member2.username)
      expect(response.body).to include(member3.username)
    end

    it "shows Discord roles for members with Discord connections" do
      # Update stub to return role for member1
      stub_request(:get, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: [role1.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      get guild_members_list_path(guild)

      expect(response).to have_http_status(:success)
      # The view should display Discord role information
    end

    it "paginates members using page and per_page params" do
      get guild_members_list_path(guild), params: { page: 1, per_page: 2 }
      expect(response).to have_http_status(:success)
      expect(assigns(:members).size).to eq(2)
      expect(assigns(:members_pagination)[:total_count]).to eq(4)
      expect(assigns(:members_pagination)[:total_pages]).to eq(2)

      get guild_members_list_path(guild), params: { page: 2, per_page: 2 }
      expect(assigns(:members).size).to eq(2)
      expect(assigns(:members_pagination)[:page]).to eq(2)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get guild_members_list_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_members_list_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-members-list-support.example/help")
        get guild_members_list_path(guild)
        expect(response.body).to include("https://guild-members-list-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-members-list-support.example/help")
        get guild_members_list_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-members-list-support.example/help")
      end
    end
  end

  describe "GET /guilds/:id/review_applications support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    it "includes default support URL in HTML" do
      get guild_review_applications_path(guild)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_review_applications_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://guild-review-applications-support.example/help")
      get guild_review_applications_path(guild)
      expect(response.body).to include("https://guild-review-applications-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://guild-review-applications-support.example/help")
      get guild_review_applications_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://guild-review-applications-support.example/help")
    end
  end

  describe "GET /guilds/:id/review_applications pagination" do
    it "paginates invites and pending applications independently" do
      3.times do
        create(:guild_invite, guild: guild, user: create(:user, auth_method: "discord"), invited_by: owner)
      end
      3.times do
        create(:guild_application, guild: guild, user: create(:user, auth_method: "discord"))
      end

      get guild_review_applications_path(guild), params: { invites_page: 1, apps_page: 1, per_page: 2 }
      expect(response).to have_http_status(:success)
      expect(assigns(:guild_invites).size).to eq(2)
      expect(assigns(:invites_pagination)[:total_count]).to eq(3)
      expect(assigns(:pending_applications).size).to eq(2)
      expect(assigns(:applications_pagination)[:total_count]).to eq(3)

      get guild_review_applications_path(guild), params: { invites_page: 2, apps_page: 2, per_page: 2 }
      expect(assigns(:guild_invites).size).to eq(1)
      expect(assigns(:pending_applications).size).to eq(1)
    end
  end

  describe "GET /guilds/:id/members/invite support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    it "includes default support URL in HTML" do
      get guild_invite_members_path(guild)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_invite_members_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://guild-invite-members-support.example/help")
      get guild_invite_members_path(guild)
      expect(response.body).to include("https://guild-invite-members-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://guild-invite-members-support.example/help")
      get guild_invite_members_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://guild-invite-members-support.example/help")
    end
  end

  describe "GET /guilds/:id/invite_members pagination" do
    it "paginates pending applications" do
      3.times do
        create(:guild_application, guild: guild, user: create(:user, auth_method: "discord"))
      end

      get guild_invite_members_path(guild), params: { apps_page: 1, per_page: 2 }
      expect(response).to have_http_status(:success)
      expect(assigns(:pending_applications).size).to eq(2)
      expect(assigns(:applications_pagination)[:total_count]).to eq(3)

      get guild_invite_members_path(guild), params: { apps_page: 2, per_page: 2 }
      expect(assigns(:pending_applications).size).to eq(1)
    end
  end

  describe "DELETE /guilds/:id/members/:member_id (kick member)" do
    it "kicks a member from the guild" do
      expect {
        delete guild_kick_member_path(guild, @guild_member1)
      }.to change { guild.guild_members.count }.by(-1)

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("removed from guild")
      expect(guild.guild_members.exists?(id: @guild_member1.id)).to be false
    end

    it "prevents kicking the guild owner" do
      owner_member = guild.guild_members.find_by(user: owner)

      expect {
        delete guild_kick_member_path(guild, owner_member)
      }.not_to change { guild.guild_members.count }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("Cannot kick the guild owner")
    end

    context "with permission system" do
      let(:permission_user) do
        u = create(:user)
        u.update!(auth_method: "discord")
        create(:user_discord_connection, user: u, discord_user_id: "permission_user_discord_id")
        u
      end
      let!(:permission_user_member) { create(:guild_member, guild: guild, user: permission_user, role: :member) }

      before do
        # Set up permission: role1 can manage roles and kick members
        guild.update!(
          permission_role_1_id: role1.role_id,
          role_1_can_manage_roles: true,
          role_1_can_kick_members: true
        )

        # Stub that permission_user has role1 in Discord - use regex to match any request
        stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/permission_user_discord_id})
          .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
          .to_return(
            status: 200,
            body: {
              user: { id: "permission_user_discord_id", username: "permissionuser" },
              roles: [role1.role_id]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "allows user with permission role to kick members" do
        sign_in permission_user
        set_mfa_verified_in_session

        # Reload guild to get updated permissions
        guild.reload

        expect {
          delete guild_kick_member_path(guild, @guild_member1)
        }.to change { guild.guild_members.count }.by(-1)

        expect(response).to redirect_to(guild_members_list_path(guild))
      end

      it "prevents user without permission role from kicking members" do
        regular_user = create(:user)
        regular_user.update!(auth_method: "discord")
        create(:user_discord_connection, user: regular_user, discord_user_id: "regular_user_discord_id")
        create(:guild_member, guild: guild, user: regular_user, role: :member)
        sign_in regular_user
        set_mfa_verified_in_session

        stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/regular_user_discord_id})
          .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
          .to_return(
            status: 200,
            body: {
              user: { id: "regular_user_discord_id", username: "regularuser" },
              roles: []
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        guild.reload

        expect {
          delete guild_kick_member_path(guild, @guild_member1)
        }.not_to change { guild.guild_members.count }

        expect(response).to redirect_to(guild_members_list_path(guild))
        expect(flash[:alert]).to include("do not have permission")
      end
    end
  end

  describe "POST /guilds/:id/members/bulk_kick" do
    it "kicks multiple members at once" do
      expect {
        post guild_bulk_kick_members_path(guild), params: {
          member_ids: [@guild_member1.id, @guild_member2.id]
        }
      }.to change { guild.guild_members.count }.by(-2)

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("2 member(s) removed")
    end

    it "does not kick owners even if selected" do
      owner_member = guild.guild_members.find_by(user: owner)

      expect {
        post guild_bulk_kick_members_path(guild), params: {
          member_ids: [@guild_member1.id, owner_member.id]
        }
      }.to change { guild.guild_members.count }.by(-1)

      expect(guild.guild_members.exists?(id: owner_member.id)).to be true
    end
  end

  describe "PATCH /guilds/:id/members/:member_id/update_role" do
    it "updates a member's Discord role ID" do
      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role1.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("Member role updated")
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id)
    end

    it "syncs role to Discord when member has Discord connection" do
      # Stub member to not have the role yet
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: []
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role1.role_id
      }

      # Verify Discord API was called to add role
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role1.role_id}")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })

      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id)
    end

    it "removes old Discord role when updating to new role" do
      # Set up member with existing role
      @guild_member1.update!(discord_role_id: role3.role_id)

      # Stub member to have old role
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: [role3.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role1.role_id
      }

      # Verify old role was removed and new role was added
      expect(WebMock).to have_requested(:delete, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role3.role_id}")
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role1.role_id}")
      
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id)
    end

    it "removes higher synced Discord roles when applying a lower matched role" do
      @guild_member1.update!(discord_role_id: role3.role_id)

      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: [role1.role_id, role3.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role2.role_id
      }

      expect(WebMock).to have_requested(:delete, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role1.role_id}")
      expect(WebMock).to have_requested(:delete, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role3.role_id}")
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role2.role_id}")

      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role2.role_id)
    end

    it "clears role when None is selected" do
      @guild_member1.update!(discord_role_id: role1.role_id)

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: ""
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to be_nil
    end

    it "prevents users from updating their own role" do
      owner_member = guild.guild_members.find_by(user: owner)
      
      patch guild_update_member_role_path(guild, owner_member), params: {
        discord_role_id: role1.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("cannot modify your own role")
    end

    it "prevents non-owners from modifying roles of users with Manage Guild Settings permission" do
      # Set up: permission_user has role1 with manage_guild_settings permission
      guild.update!(
        permission_role_1_id: role1.role_id,
        role_1_can_manage_guild_settings: true
      )
      
      # Set up: @guild_member1 has role1 (so they have manage_guild_settings permission)
      @guild_member1.update!(discord_role_id: role1.role_id)
      
      # Stub that @guild_member1's user has role1 in Discord
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: [role1.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Try to update role as a non-owner (permission_user)
      permission_user = create(:user)
      permission_user.update!(auth_method: "discord")
      create(:user_discord_connection, user: permission_user, discord_user_id: "perm_user_discord_id")
      create(:guild_member, guild: guild, user: permission_user, role: :member)
      
      # Set up permission_user to have manage_roles permission but not be owner
      guild.update!(
        permission_role_2_id: role2.role_id,
        role_2_can_manage_roles: true
      )
      
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/perm_user_discord_id})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "perm_user_discord_id", username: "permuser" },
            roles: [role2.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      sign_in permission_user
      set_mfa_verified_in_session
      guild.reload

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role2.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("Only the guild owner can modify the role of users with guild settings permissions")
      
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id) # Should not have changed
    end

    it "allows owner to modify roles of users with Manage Guild Settings permission" do
      # Set up: @guild_member1 has role1 with manage_guild_settings permission
      guild.update!(
        permission_role_1_id: role1.role_id,
        role_1_can_manage_guild_settings: true
      )
      
      @guild_member1.update!(discord_role_id: role1.role_id)
      
      # Owner can modify it
      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role2.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("Member role updated")
      
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role2.role_id)
    end
  end

  describe "POST /guilds/:id/members/bulk_update_roles" do
    it "updates multiple members' Discord roles at once" do
      # Stub members to not have the role yet
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_[12]})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: []
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [@guild_member1.id, @guild_member2.id],
        discord_role_id: role1.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("2 member(s) role updated")

      @guild_member1.reload
      @guild_member2.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id)
      expect(@guild_member2.discord_role_id).to eq(role1.role_id)
    end

    it "syncs roles to Discord for all updated members" do
      # Stub members to not have the role yet
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_[12]})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: []
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [@guild_member1.id, @guild_member2.id],
        discord_role_id: role1.role_id
      }

      # Verify Discord API was called for both members
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role1.role_id}")
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_2/roles/#{role1.role_id}")
    end

    it "removes higher synced roles in bulk updates" do
      @guild_member1.update!(discord_role_id: role3.role_id)

      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "discord_user_1", username: "testuser" },
            roles: [role1.role_id, role3.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [@guild_member1.id],
        discord_role_id: role2.role_id
      }

      expect(WebMock).to have_requested(:delete, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role1.role_id}")
      expect(WebMock).to have_requested(:delete, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role3.role_id}")
      expect(WebMock).to have_requested(:put, "https://discord.com/api/v10/guilds/#{discord_guild_id}/members/discord_user_1/roles/#{role2.role_id}")
    end

    it "allows clearing roles when None is selected" do
      @guild_member1.update!(discord_role_id: role1.role_id)
      @guild_member2.update!(discord_role_id: role2.role_id)

      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [@guild_member1.id, @guild_member2.id],
        discord_role_id: ""
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("2 member(s) role updated")

      @guild_member1.reload
      @guild_member2.reload
      expect(@guild_member1.discord_role_id).to be_nil
      expect(@guild_member2.discord_role_id).to be_nil
    end

    it "requires at least one member to be selected" do
      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [],
        discord_role_id: role1.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to include("No members selected")
    end

    it "does not update owners even if selected" do
      owner_member = guild.guild_members.find_by(user: owner)

      post guild_bulk_update_member_roles_path(guild), params: {
        member_ids: [@guild_member1.id, owner_member.id],
        discord_role_id: role1.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role1.role_id)
      # Owner should not be updated
      owner_member.reload
      expect(owner_member.discord_role_id).not_to eq(role1.role_id)
    end
  end

  describe "Permission Settings" do
    describe "GET /guilds/:id/settings" do
      it "displays permission settings when Discord is connected" do
        get guild_settings_path(guild)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Role Permissions")
        expect(response.body).to include("Role 1")
        expect(response.body).to include("Role 2")
      end
    end

    describe "PATCH /guilds/:id (update permission settings)" do
      it "saves permission settings" do
        patch update_guild_path(guild), params: {
          guild: {
            permission_role_1_id: role1.role_id,
            role_1_can_manage_roles: true,
            role_1_can_manage_applications: true,
            role_1_can_manage_guild_settings: false,
            permission_role_2_id: role2.role_id,
            role_2_can_manage_roles: false,
            role_2_can_manage_applications: true,
            role_2_can_manage_guild_settings: true
          },
          commit: "Save Permissions"
        }

        expect(response).to redirect_to(guild_settings_path(guild))
        expect(flash[:notice]).to include("updated successfully")

        guild.reload
        expect(guild.permission_role_1_id).to eq(role1.role_id)
        expect(guild.role_1_can_manage_roles).to be true
        expect(guild.role_1_can_manage_applications).to be true
        expect(guild.role_1_can_manage_guild_settings).to be false
        expect(guild.permission_role_2_id).to eq(role2.role_id)
        expect(guild.role_2_can_manage_roles).to be false
        expect(guild.role_2_can_manage_applications).to be true
        expect(guild.role_2_can_manage_guild_settings).to be true
      end

      it "prevents non-owners from modifying their own role's permissions" do
        # Set up: permission_user has role1 with manage_guild_settings permission
        permission_user = create(:user)
        permission_user.update!(auth_method: "discord")
        create(:user_discord_connection, user: permission_user, discord_user_id: "perm_user_discord_id")
        permission_member = create(:guild_member, guild: guild, user: permission_user, role: :member, discord_role_id: role1.role_id)
        
        guild.update!(
          permission_role_1_id: role1.role_id,
          role_1_can_manage_guild_settings: true
        )

        stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/perm_user_discord_id})
          .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
          .to_return(
            status: 200,
            body: {
              user: { id: "perm_user_discord_id", username: "permuser" },
              roles: [role1.role_id]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        sign_in permission_user
        set_mfa_verified_in_session
        guild.reload

        # Try to modify role1's permissions (which is permission_user's own role)
        patch update_guild_path(guild), params: {
          guild: {
            permission_role_1_id: role1.role_id,
            role_1_can_manage_roles: false,
            role_1_can_manage_applications: false,
            role_1_can_manage_guild_settings: false
          },
          commit: "Save Permissions"
        }

        expect(response).to redirect_to(guild_settings_path(guild))
        expect(flash[:alert]).to include("Only the guild owner can modify your role's permissions")
        
        guild.reload
        # Permissions should not have changed
        expect(guild.role_1_can_manage_guild_settings).to be true
      end

      it "allows owner to modify any role's permissions" do
        # Set up existing permissions
        guild.update!(
          permission_role_1_id: role1.role_id,
          role_1_can_manage_roles: true,
          role_1_can_manage_guild_settings: true
        )

        # Owner can modify role1's permissions
        patch update_guild_path(guild), params: {
          guild: {
            permission_role_1_id: role1.role_id,
            role_1_can_manage_roles: false,
            role_1_can_manage_applications: true,
            role_1_can_manage_guild_settings: false
          },
          commit: "Save Permissions"
        }

        expect(response).to redirect_to(guild_settings_path(guild))
        expect(flash[:notice]).to include("updated successfully")
        
        guild.reload
        expect(guild.role_1_can_manage_roles).to be false
        expect(guild.role_1_can_manage_applications).to be true
        expect(guild.role_1_can_manage_guild_settings).to be false
      end

      it "rejects selecting the same discord role in multiple permission slots" do
        guild.update!(
          permission_role_1_id: role1.role_id,
          permission_role_2_id: role2.role_id
        )

        patch update_guild_path(guild), params: {
          guild: {
            permission_role_1_id: role1.role_id,
            permission_role_2_id: role1.role_id,
            role_1_can_manage_roles: true,
            role_2_can_manage_applications: true
          },
          commit: "Save Permissions"
        }

        expect(response).to redirect_to(guild_settings_path(guild))
        expect(flash[:alert]).to eq("This role has already been selected!")

        guild.reload
        expect(guild.permission_role_1_id).to eq(role1.role_id)
        expect(guild.permission_role_2_id).to eq(role2.role_id)
      end
    end
  end

  describe "Permission Enforcement" do
    let(:permission_user) do
      u = create(:user)
      u.update!(auth_method: "discord")
      create(:user_discord_connection, user: u, discord_user_id: "permission_user_discord_id")
      u
    end
    let!(:permission_user_member) { create(:guild_member, guild: guild, user: permission_user, role: :member) }

    before do
      # Set up permission: role1 can manage roles and applications
      guild.update!(
        permission_role_1_id: role1.role_id,
        role_1_can_manage_roles: true,
        role_1_can_manage_applications: true,
        role_1_can_manage_guild_settings: false
      )

      # Stub that permission_user has role1 in Discord - use regex to match
      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/permission_user_discord_id})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "permission_user_discord_id", username: "permissionuser" },
            roles: [role1.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "allows permission user to manage roles" do
      sign_in permission_user
      set_mfa_verified_in_session

      # Reload guild to get updated permissions
      guild.reload

      patch guild_update_member_role_path(guild, @guild_member1), params: {
        discord_role_id: role2.role_id
      }

      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to include("Member role updated")
      @guild_member1.reload
      expect(@guild_member1.discord_role_id).to eq(role2.role_id)
    end

    it "prevents permission user from managing guild settings" do
      sign_in permission_user
      set_mfa_verified_in_session

      # Reload guild to get updated permissions
      guild.reload

      patch update_guild_path(guild), params: {
        guild: { name: "New Name" },
        commit: "Save Messages"
      }

      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to include("do not have permission")
      expect(guild.reload.name).not_to eq("New Name")
    end

    it "allows permission user to manage applications when permission is granted" do
      sign_in permission_user
      set_mfa_verified_in_session

      # Remove member1 from guild first to avoid duplicate member error
      @guild_member1.destroy
      application = create(:guild_application, guild: guild, user: member1, status: :pending)

      # Stub Discord DM for acceptance message
      stub_request(:post, "https://discord.com/api/v10/users/@me/channels")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: { id: "dm_channel_id" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:post, "https://discord.com/api/v10/channels/dm_channel_id/messages")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(status: 200, body: {}.to_json)

      patch accept_guild_application_path(application)

      expect(response).to redirect_to(guild_invite_members_path(guild))
      expect(flash[:notice]).to include("accepted")
    end
  end

  describe "Application Management Permissions" do
    let(:application_user) do
      u = create(:user)
      u.update!(auth_method: "discord")
      create(:user_discord_connection, user: u, discord_user_id: "app_user_discord_id")
      u
    end
    let!(:application_user_member) { create(:guild_member, guild: guild, user: application_user, role: :member) }
    let(:application) { create(:guild_application, guild: guild, user: member1, status: :pending) }

    before do
      # Set up permission: role2 can manage applications
      guild.update!(
        permission_role_2_id: role2.role_id,
        role_2_can_manage_applications: true
      )

      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/app_user_discord_id})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "app_user_discord_id", username: "appuser" },
            roles: [role2.role_id]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "allows user with application permission to accept applications" do
      sign_in application_user
      set_mfa_verified_in_session

      # Remove member1 from guild first to avoid duplicate member error
      @guild_member1.destroy
      application.reload

      # Stub Discord DM for acceptance message
      stub_request(:post, "https://discord.com/api/v10/users/@me/channels")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: { id: "dm_channel_id" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:post, "https://discord.com/api/v10/channels/dm_channel_id/messages")
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(status: 200, body: {}.to_json)

      expect {
        patch accept_guild_application_path(application)
      }.to change { guild.guild_members.count }.by(1)

      expect(response).to redirect_to(guild_invite_members_path(guild))
    end

    it "prevents user without application permission from accepting applications" do
      regular_user = create(:user)
      regular_user.update!(auth_method: "discord")
      create(:user_discord_connection, user: regular_user, discord_user_id: "regular_user_discord_id")
      create(:guild_member, guild: guild, user: regular_user, role: :member)
      sign_in regular_user
      set_mfa_verified_in_session

      stub_request(:get, %r{https://discord\.com/api/v10/guilds/#{discord_guild_id}/members/regular_user_discord_id})
        .with(headers: { "Authorization" => "Bot #{fake_bot_token}" })
        .to_return(
          status: 200,
          body: {
            user: { id: "regular_user_discord_id", username: "regularuser" },
            roles: []
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect {
        patch accept_guild_application_path(application)
      }.not_to change { guild.guild_members.count }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end
end
