# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Guild Applications", type: :request do
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
    # Set auth_method to "discord" to bypass MFA checks in tests
    u.update!(auth_method: "discord")
    u
  end
  let(:applicant) do
    u = create(:user)
    # Set auth_method to "discord" to bypass MFA checks in tests
    u.update!(auth_method: "discord")
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:owner_subscription) { create(:subscription, user: owner, pricing_plan: pricing_plan) }
  let!(:applicant_subscription) { create(:subscription, user: applicant, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: owner) }

  describe "GET /guild_applications" do
    before do
      sign_in applicant
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "lists applications for user's guilds" do
      application = create(:guild_application, guild: guild, user: applicant)
      
      get "/guild_applications"
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include(guild.name)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        create(:guild_application, guild: guild, user: applicant)
        get "/guild_applications"
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        create(:guild_application, guild: guild, user: applicant)
        get "/guild_applications", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        create(:guild_application, guild: guild, user: applicant)
        SiteSetting.set("release_notes_url", "https://guild-applications-support.example/help")
        get "/guild_applications"
        expect(response.body).to include("https://guild-applications-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        create(:guild_application, guild: guild, user: applicant)
        SiteSetting.set("release_notes_url", "https://guild-applications-support.example/help")
        get "/guild_applications", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-applications-support.example/help")
      end
    end
  end

  describe "GET /guild_applications/new" do
    before do
      sign_in applicant
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get new_guild_application_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get new_guild_application_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-applications-new-support.example/help")
        get new_guild_application_path
        expect(response.body).to include("https://guild-applications-new-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-applications-new-support.example/help")
        get new_guild_application_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-applications-new-support.example/help")
      end
    end

    it "pre-fills Discord username with global display name when connected" do
      applicant.update!(discord_global_name: "Grimmjow", discord_username: "api_fallback")
      create(:user_discord_connection, user: applicant, discord_username: "login_name")
      get new_guild_application_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('value="Grimmjow"')
    end

    it "pre-fills with connection login name when global name is absent" do
      applicant.update!(discord_global_name: nil)
      create(:user_discord_connection, user: applicant, discord_username: "login_only")
      get new_guild_application_path
      expect(response.body).to include('value="login_only"')
    end

    it "does not pre-fill when Discord is not connected" do
      applicant.update!(discord_global_name: "Ghost", discord_username: "x")
      get new_guild_application_path
      expect(response.body).not_to include('value="Ghost"')
    end
  end

  describe "POST /guild_applications" do
    before do
      sign_in applicant
    end

    it "creates application to join guild" do
      expect {
        post "/guild_applications", params: {
          guild_id: guild.id,
          discord_username: "TestUser#1234",
          message: "I would like to join"
        }
      }.to change { GuildApplication.count }.by(1)
      
      expect(response).to redirect_to(guild_applications_path)
      application = GuildApplication.last
      expect(application.user).to eq(applicant)
      expect(application.guild).to eq(guild)
      expect(application.status).to eq("pending")
    end

    it "prevents applying to a guild the user is already a member of" do
      create(:guild_member, guild: guild, user: applicant, status: :active)

      post "/guild_applications", params: {
        guild_id: guild.id,
        discord_username: "TestUser#1234",
        message: "I would like to join"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to include("Silly goose")
    end

    it "rejects applications to a privately listed guild" do
      guild.update!(publicly_listed: false)

      expect {
        post "/guild_applications", params: {
          guild_id: guild.id,
          discord_username: "TestUser#1234",
          message: "I would like to join"
        }
      }.not_to change { GuildApplication.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq(I18n.t("guild_applications.create.guild_not_available"))
    end

    it "rejects applications to an archived public guild" do
      guild.update!(archived_at: Time.current, scheduled_purge_at: 1.year.from_now)

      expect {
        post "/guild_applications", params: {
          guild_id: guild.id,
          discord_username: "TestUser#1234",
          message: "I would like to join"
        }
      }.not_to change { GuildApplication.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq(I18n.t("guild_applications.create.guild_not_available"))
    end

    it "allows re-applying after rejection" do
      # Create and reject an application
      rejected_app = create(:guild_application, guild: guild, user: applicant, status: :rejected)

      expect {
        post "/guild_applications", params: {
          guild_id: guild.id,
          discord_username: "TestUser#1234",
          message: "I would like to join again"
        }
      }.to change { GuildApplication.count }.by(1)
      
      expect(response).to redirect_to(guild_applications_path)
      new_application = GuildApplication.last
      expect(new_application.status).to eq("pending")
      expect(new_application.id).not_to eq(rejected_app.id)
    end

    it "prevents multiple pending applications to the same guild" do
      create(:guild_application, guild: guild, user: applicant, status: :pending)

      expect {
        post "/guild_applications", params: {
          guild_id: guild.id,
          discord_username: "TestUser#1234",
          message: "I would like to join"
        }
      }.not_to change { GuildApplication.count }
      
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /guild_applications/:id/accept" do
    let(:application) { create(:guild_application, guild: guild, user: applicant) }

    before do
      sign_in owner
    end

    it "redirects when the application id is unknown" do
      patch "/guild_applications/999_999_999/accept"
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects when the application belongs to another guild" do
      other_owner = create(:user)
      other_owner.update!(auth_method: "discord")
      create(:subscription, user: other_owner, pricing_plan: pricing_plan)
      other_guild = create(:guild, owner: other_owner)
      foreign_app = create(:guild_application, guild: other_guild, user: applicant, status: :pending)

      patch "/guild_applications/#{foreign_app.id}/accept"
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
      expect(foreign_app.reload.status).to eq("pending")
    end

    it "accepts application and adds user to guild" do
      patch "/guild_applications/#{application.id}/accept"
      
      expect(response).to redirect_to(guild_invite_members_path(guild))
      expect(flash[:notice]).to include("Member accepted")
      application.reload
      expect(application.status).to eq("accepted")
      expect(guild.members).to include(applicant)
    end

    it "handles accepting application when user is already a member" do
      # User is already a member (maybe was added via invite)
      create(:guild_member, guild: guild, user: applicant, status: :active)

      patch "/guild_applications/#{application.id}/accept"
      
      expect(response).to redirect_to(guild_invite_members_path(guild))
      expect(flash[:notice]).to include("Member accepted")
      application.reload
      expect(application.status).to eq("accepted")
      # User should still be a member
      expect(guild.members).to include(applicant)
    end

    context "with Discord connection" do
      let!(:discord_connection) do
        create(:user_discord_connection, user: applicant, discord_user_id: "applicant_discord_id")
      end
      let!(:guild_discord_setting) do
        create(:guild_discord_setting, guild: guild, discord_guild_id: "discord_guild_id", connected_at: Time.current)
      end

      before do
        # Stub Discord API calls
        stub_request(:get, %r{https://discord\.com/api/v10/guilds/discord_guild_id/members/applicant_discord_id})
          .to_return(status: 200, body: { user: { id: "applicant_discord_id" }, roles: [] }.to_json, headers: { "Content-Type" => "application/json" })
        stub_request(:post, %r{https://discord\.com/api/v10/users/@me/channels})
          .to_return(status: 200, body: { id: "dm_channel_id" }.to_json, headers: { "Content-Type" => "application/json" })
        stub_request(:post, %r{https://discord\.com/api/v10/channels/dm_channel_id/messages})
          .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "sends Discord notification when accepting application" do
        patch "/guild_applications/#{application.id}/accept"
        
        expect(WebMock).to have_requested(:post, %r{https://discord\.com/api/v10/users/@me/channels})
        expect(WebMock).to have_requested(:post, %r{https://discord\.com/api/v10/channels/dm_channel_id/messages})
          .with(body: hash_including(content: /Application Accepted/))
      end
    end
  end

  describe "PATCH /guild_applications/:id/reject" do
    let(:application) { create(:guild_application, guild: guild, user: applicant) }

    before do
      sign_in owner
    end

    it "rejects application" do
      patch "/guild_applications/#{application.id}/reject"
      
      expect(response).to redirect_to(guild_invite_members_path(guild))
      application.reload
      expect(application.status).to eq("rejected")
      expect(guild.members).not_to include(applicant)
    end
  end
end

