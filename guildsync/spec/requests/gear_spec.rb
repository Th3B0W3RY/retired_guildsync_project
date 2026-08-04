# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Gear API', type: :request do
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

  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }
  let(:game) { guild.games.first } # Guild factory creates a game
  let(:target_user) { create(:user) }
  
  before do
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    # Add target_user as a guild member
    guild.guild_members.create!(user: target_user, role: :member, status: :active)
  end
  
  describe 'POST /guilds/:id/gear/upload' do
    # Create a minimal valid PNG file for testing
    let(:image_file) do
      png_data = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
        0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
        0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ].pack('C*')
      
      file = Tempfile.new(['test_image', '.png'])
      file.binmode
      file.write(png_data)
      file.rewind
      
      # Use Rack::Test::UploadedFile for request specs
      Rack::Test::UploadedFile.new(file.path, 'image/png')
    end
    
    before do
      # Mock OCR and embedding services to avoid actual Python calls
      allow(GearOcrService).to receive(:process_image).and_return({
        success: true,
        raw_text: "Gear Score: 1642\nWeapon 1: Shadowblade +10",
        data: { 'Gear Score' => 1642, 'Weapon 1' => 'Shadowblade +10' }
      })
      allow(GearEmbeddingService).to receive(:generate_embedding).and_return([0.1, 0.2, 0.3])
      allow(GearEmbeddingService).to receive(:validate_embedding).and_return({ valid: true, warning: nil })
    end
    
    it 'uploads and processes gear screenshot' do
      expect {
        post guild_gear_upload_path(guild), params: {
          screenshot: image_file
        }
      }.to change { GearSnapshot.count }.by(1)
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['snapshot']).to be_present
      expect(json['snapshot']['id']).to be_present
      expect(json['snapshot']['last_activity_at']).to be_present
    end

    it 'bumps the uploader guild membership updated_at after a successful upload' do
      gm = guild.guild_members.find_by!(user: user)
      expect {
        post guild_gear_upload_path(guild), params: { screenshot: image_file }
      }.to change { gm.reload.updated_at }
      expect(response).to have_http_status(:success)
    end

    it 'persists a new snapshot on each upload so the same file can be re-sent and becomes the latest record' do
      post guild_gear_upload_path(guild), params: { screenshot: image_file }
      expect(response).to have_http_status(:success)
      first_id = JSON.parse(response.body).dig("snapshot", "id")

      image_file.rewind
      post guild_gear_upload_path(guild), params: { screenshot: image_file }
      expect(response).to have_http_status(:success)
      second_id = JSON.parse(response.body).dig("snapshot", "id")

      expect(second_id).not_to eq(first_id)
      expect(GearSnapshot.where(guild: guild, user: user).order(created_at: :desc).pick(:id)).to eq(second_id)
    end
    
    it 'requires screenshot parameter' do
      post guild_gear_upload_path(guild), params: {}
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq(
        "#{I18n.t('gear.api.screenshot_required')} #{I18n.t('gear.api.reach_guildsync_support')}"
      )
    end
    
    it 'validates file type' do
      invalid_file = Tempfile.new(['test', '.txt'])
      invalid_file.write('not an image')
      invalid_file.rewind
      
      post guild_gear_upload_path(guild), params: {
        screenshot: Rack::Test::UploadedFile.new(invalid_file.path, 'text/plain')
      }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq(
        "#{I18n.t('gear.api.invalid_file_type')} #{I18n.t('gear.api.reach_guildsync_support')}"
      )
    end
    
    it 'marks pending requests as completed after upload' do
      # Create a pending request
      request = create(:gear_upload_request,
        guild: guild,
        requester: user,
        target_user: user,
        status: :pending
      )
      
      post guild_gear_upload_path(guild), params: {
        screenshot: image_file
      }
      
      expect(response).to have_http_status(:success)
      request.reload
      expect(request.status).to eq('completed')
      expect(request.completed_at).to be_present
    end
    
    it 'handles OCR failures gracefully' do
      allow(GearOcrService).to receive(:process_image).and_return({
        success: false,
        error: 'OCR processing failed'
      })
      
      post guild_gear_upload_path(guild), params: {
        screenshot: image_file
      }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq(
        "#{I18n.t('gear.api.ocr_failed')} #{I18n.t('gear.api.reach_guildsync_support')}"
      )
    end

    context 'when OCR succeeds but no stats can be parsed (e.g. wrong panel captured)' do
      before do
        allow(GearOcrService).to receive(:process_image).and_return({
          success: true,
          raw_text: "some unreadable HUD text",
          data: {}
        })
      end

      it 'still saves the snapshot but reports stats_extracted false with a warning' do
        expect {
          post guild_gear_upload_path(guild), params: { screenshot: image_file }
        }.to change { GearSnapshot.count }.by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["stats_extracted"]).to be false
        expect(json.dig("snapshot", "validation_warning")).to eq(I18n.t("gear.api.stats_not_extracted"))
        expect(json.dig("snapshot", "data")).to eq({})
      end
    end

    it 'reports stats_extracted true when stats are parsed' do
      post guild_gear_upload_path(guild), params: { screenshot: image_file }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["stats_extracted"]).to be true
    end

    context 'JSON auth contract for fetch uploads' do
      it 'returns 401 JSON when not signed in (no redirect to login)' do
        sign_out :user

        post guild_gear_upload_path(guild),
          params: { screenshot: image_file },
          headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.media_type).to eq("application/json")
        expect(response).not_to be_redirect
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.authentication_required"))
      end

      context 'when an MFA user has not verified this session' do
        let(:mfa_user) { create(:user, :with_mfa, auth_method: "mfa") }

        before do
          sign_out :user
          guild.guild_members.find_or_create_by!(user: mfa_user) do |gm|
            gm.role = :member
            gm.status = :active
          end
          sign_in mfa_user
          allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(false)
          allow(User).to receive(:skip_mfa_verification?).and_return(false)
          get dashboard_path rescue nil
          session[:mfa_verified] = false
          session.delete(:mfa_verified_at)
        end

        it 'returns 403 JSON without redirecting to MFA verification' do
          post guild_gear_upload_path(guild),
            params: { screenshot: image_file },
            headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:forbidden)
          expect(response.media_type).to eq("application/json")
          expect(response).not_to be_redirect
          expect(response.parsed_body["error"]).to eq(I18n.t("gear.api.mfa_required"))
        end
      end
    end

    it 'captures unexpected upload exceptions in ErrorLogger' do
      allow(GearOcrService).to receive(:process_image).and_raise(RuntimeError.new('unexpected'))
      expect(ErrorLogger).to receive(:capture).with(
        instance_of(RuntimeError),
        hash_including(
          severity: 'high',
          context: hash_including(component: 'GearController#upload', guild_id: guild.id, user_id: user.id)
        )
      )
      post guild_gear_upload_path(guild), params: {
        screenshot: image_file
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'passes current user, guild, and Rack request to GearOcrService for quota and IP checks' do
      expect(GearOcrService).to receive(:process_image) do |_file, passed_game, **kwargs|
        expect(passed_game).to eq(game)
        expect(kwargs[:user]).to eq(user)
        expect(kwargs[:guild]).to eq(guild)
        expect(kwargs[:request]).to be_a(ActionDispatch::Request)
        { success: true, raw_text: "Gear Score: 1", data: { "Gear Score" => 1 } }
      end

      post guild_gear_upload_path(guild), params: {
        screenshot: image_file
      }

      expect(response).to have_http_status(:success)
    end

    context 'when a member uploads and the guild owner provides the paid OCR pool' do
      let(:owner_user) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
      let(:member_user) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
      let(:upgraded_plan) do
        PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
          create(:pricing_plan,
            name: "Upgraded",
            price: 16,
            price_display: "$16",
            period: "per month",
            max_guilds: nil,
            max_members_per_guild: nil,
            active: true,
            display_order: 97)
      end
      let(:free_plan) do
        PricingPlan.where("LOWER(TRIM(name)) = ?", "free").first ||
          create(:pricing_plan, name: "Free", price: 0, max_guilds: 1, max_members_per_guild: 5, active: true, display_order: 1)
      end

      let!(:guild) do
        owner_user.subscribe_to_plan!(upgraded_plan)
        create(:guild, owner: owner_user)
      end

      before do
        member_user.subscribe_to_plan!(free_plan)
        create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
        sign_in member_user
        allow(GearOcrService).to receive(:process_image).and_call_original
        stub_ocr = "Shared pool: 1"
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return(stub_ocr)
        allow(Ocr::SuryaOcrService).to receive(:extract_text).and_return(stub_ocr)
        allow(Ocr::TesseractOcrService).to receive(:extract_text).and_return(stub_ocr)
      end

      it 'increments OCR usage on the guild owner, not the member' do
        skip 'User has no OCR billing columns' unless User.column_names.include?("ocr_billing_plan")

        owner_user.update_columns(
          ocr_billing_plan: "upgraded",
          ocr_requests_used_this_period: 0,
          ocr_last_reset_at: Time.current.beginning_of_month
        )
        member_user.update_columns(ocr_billing_plan: "free", ocr_requests_used_this_period: 0)

        expect {
          post guild_gear_upload_path(guild), params: { screenshot: image_file }
        }.to change { owner_user.reload.ocr_requests_used_this_period }.by(1)

        expect(response).to have_http_status(:success)
        expect(member_user.reload.ocr_requests_used_this_period).to eq(0)
      end
    end

    context 'when user is at OCR monthly limit (trial)' do
      before do
        skip 'User has no OCR billing columns' unless User.column_names.include?("ocr_billing_plan")

        user.update_columns(ocr_billing_plan: "trial", ocr_requests_used_this_period: 3)
        allow(GearOcrService).to receive(:process_image).and_call_original
      end

      it 'returns unprocessable entity without running the OCR engine' do
        expect(Ocr::AzureOcrService).not_to receive(:extract_text)

        expect {
          post guild_gear_upload_path(guild), params: {
            screenshot: image_file
          }
        }.not_to change(GearSnapshot, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to include(I18n.t("gear.api.ocr_failed"))
        expect(json["error"]).to include(I18n.t("gear.api.reach_guildsync_support"))
        expect(json["details"]).to be_present
      end
    end
  end
  
  describe 'GET /guilds/:id/gear/:user_id' do
    context 'when user has gear snapshot' do
      let!(:snapshot) do
        create(:gear_snapshot,
          guild: guild,
          user: target_user,
          game: game,
          data: { 'Gear Score' => 1642 }
        )
      end
      
      it 'returns user gear snapshot' do
        get guild_gear_show_path(guild, target_user)
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['user']).to be_present
        expect(json['snapshot']).to be_present
        expect(json['snapshot']['id']).to eq(snapshot.id)
        expect(json['snapshot']['last_activity_at']).to be_present
      end
    end
    
    context 'when user has no gear snapshot' do
      it 'returns nil snapshot' do
        get guild_gear_show_path(guild, target_user)
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['snapshot']).to be_nil
      end
    end
    
    context 'when user is not a guild member' do
      let(:non_member) { create(:user) }
      
      it 'returns 404 with access_denied (no user id leak)' do
        get guild_gear_show_path(guild, non_member)
        
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end
    
    context 'when user does not exist' do
      it 'returns 404 with access_denied' do
        get guild_gear_show_path(guild, 99999)
        
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end

    context 'when a member tries to view another member\'s gear JSON' do
      # Peer must use Discord auth so MFA before_action does not redirect (302) before the JSON response.
      let(:target_user) { create(:user, :discord_auth) }

      let!(:owner_snapshot) do
        create(:gear_snapshot,
          guild: guild,
          user: user,
          game: game,
          data: { 'Level' => '60' })
      end

      it 'returns forbidden' do
        sign_in target_user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

        get guild_gear_show_path(guild, user), headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq(I18n.t("guilds.member_stats.cannot_view_other_member_stats"))
      end
    end
  end

  describe "GET /guilds/:id/gear/:user_id/screenshot" do
    let!(:snapshot) do
      create(:gear_snapshot,
        guild: guild,
        user: target_user,
        game: game,
        data: { "Gear Score" => 1 })
    end

    it "redirects to Active Storage when the viewer may access that member's stats" do
      get guild_gear_screenshot_path(guild, target_user)
      expect(response).to have_http_status(:found)
      expect(response.location).to include("rails/active_storage")
    end

    it "redirects with alert when the snapshot is past the retention period" do
      snapshot.update_column(:created_at, (GearSnapshot::RETENTION_PERIOD_DAYS + 1).days.ago)
      get guild_gear_screenshot_path(guild, target_user)
      expect(response).to redirect_to(guild_members_gear_path(guild))
      expect(flash[:alert]).to eq(I18n.t("guilds.members_gear.screenshot_unavailable"))
    end

    context "when a member tries to open another member's screenshot" do
      let(:other_member) { create(:user, :discord_auth) }

      before do
        guild.guild_members.create!(user: other_member, role: :member, status: :active)
        sign_in other_member
      end

      let!(:owner_snapshot) do
        create(:gear_snapshot,
          guild: guild,
          user: user,
          game: game,
          data: { "Level" => "60" })
      end

      it "redirects with the same messaging as viewing other members' stats" do
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
        get guild_gear_screenshot_path(guild, user)
        expect(response).to redirect_to(guild_members_gear_path(guild))
        expect(flash[:alert]).to eq(I18n.t("guilds.member_stats.cannot_view_other_member_stats"))
      end
    end
  end
  
  describe 'POST /guilds/:id/gear/request' do
    it 'creates gear upload request' do
      expect {
        post guild_gear_request_path(guild), params: {
          user_id: target_user.id
        }
      }.to change { GearUploadRequest.count }.by(1)
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["request_id"]).to be_present
      expect(json["message"]).to eq(I18n.t("gear.api.request_created", name: target_user.display_name))
    end
    
    it 'prevents duplicate pending requests' do
      create(:gear_upload_request,
        guild: guild,
        requester: user,
        target_user: target_user,
        status: :pending
      )
      
      expect {
        post guild_gear_request_path(guild), params: {
          user_id: target_user.id
        }
      }.not_to change { GearUploadRequest.count }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["success"]).to be false
      expect(json["message"]).to eq(I18n.t("gear.api.request_already_pending", name: target_user.display_name))
    end
    
    it 'returns 404 when target user is not a guild member' do
      non_member = create(:user)
      
      post guild_gear_request_path(guild), params: {
        user_id: non_member.id
      }
      
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to eq(I18n.t("controllers.guilds.access_denied"))
    end
    
    it 'returns 404 for invalid user id' do
      post guild_gear_request_path(guild), params: {
        user_id: 99999
      }
      
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to eq(I18n.t("controllers.guilds.access_denied"))
    end
    
    it 'enqueues Discord notification job' do
      expect(DiscordGearRequestJob).to receive(:perform_later).once
      
      post guild_gear_request_path(guild), params: {
        user_id: target_user.id
      }
      
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'POST /guilds/:id/gear/request_bulk' do
    let(:member1) { create(:user) }
    let(:member2) { create(:user) }
    let(:member3) { create(:user) }
    
    before do
      guild.guild_members.create!(user: member1, role: :member, status: :active)
      guild.guild_members.create!(user: member2, role: :member, status: :active)
      guild.guild_members.create!(user: member3, role: :member, status: :active)
      
      # Create some snapshots
      create(:gear_snapshot, guild: guild, user: member1, game: game, created_at: 10.days.ago) # outdated
      create(:gear_snapshot, guild: guild, user: member2, game: game, created_at: 1.day.ago) # up to date
      # member3 has no snapshot (missing)
    end
    
    it 'creates requests for missing gear' do
      # Count existing requests
      initial_count = GearUploadRequest.count
      
      post guild_gear_request_bulk_path(guild), params: {
        status: 'missing'
      }
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      # Should create requests for member3 (missing) and possibly user/target_user if they have no snapshots
      # Let's check that at least member3 got a request
      expect(GearUploadRequest.where(guild: guild, target_user: member3).count).to eq(1)
      expect(json['count']).to be >= 1
    end
    
    it 'creates requests for outdated gear' do
      expect {
        post guild_gear_request_bulk_path(guild), params: {
          status: 'outdated'
        }
      }.to change { GearUploadRequest.count }.by(1) # Only member1
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['count']).to eq(1)
    end
    
    it 'creates requests for both missing and outdated when status is all' do
      # Count existing requests
      initial_count = GearUploadRequest.count
      
      post guild_gear_request_bulk_path(guild), params: {
        status: 'all'
      }
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      # Should create requests for member1 (outdated) and member3 (missing)
      # Plus possibly user/target_user if they have no snapshots or outdated ones
      expect(GearUploadRequest.where(guild: guild, target_user: member1).count).to eq(1)
      expect(GearUploadRequest.where(guild: guild, target_user: member3).count).to eq(1)
      expect(json['count']).to be >= 2
    end
    
    it 'enqueues bulk processing job' do
      expect(DiscordBulkGearRequestJob).to receive(:perform_later).once
      
      post guild_gear_request_bulk_path(guild), params: {
        status: 'missing'
      }
      
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'permissions' do
    let(:regular_member) do
      u = create(:user)
      u.update!(auth_method: "discord")
      u
    end
    
    before do
      guild.guild_members.create!(user: regular_member, role: :member, status: :active)
    end
    
    context 'when user is not a guild member' do
      let(:non_member) do
        u = create(:user)
        u.update!(auth_method: "discord")
        u
      end
      
      before { sign_in non_member }
      
      it 'cannot upload gear' do
        post guild_gear_upload_path(guild), params: {}

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end

      it 'cannot view gear' do
        get guild_gear_show_path(guild, target_user)

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end
    
    context 'when user is a regular member' do
      before { sign_in regular_member }
      
      it 'can upload their own gear' do
        # Mock services
        allow(GearOcrService).to receive(:process_image).and_return({
          success: true,
          raw_text: "Gear Score: 1642",
          data: { 'Gear Score' => 1642 }
        })
        allow(GearEmbeddingService).to receive(:generate_embedding).and_return([0.1, 0.2, 0.3])
        allow(GearEmbeddingService).to receive(:validate_embedding).and_return({ valid: true, warning: nil })
        
        file = Tempfile.new(['test', '.png'])
        file.binmode
        file.write('fake png')
        file.rewind
        image_file = Rack::Test::UploadedFile.new(file.path, 'image/png')
        
        post guild_gear_upload_path(guild), params: {
          screenshot: image_file
        }
        
        expect(response).to have_http_status(:success)
      end
      
      it 'cannot request gear updates' do
        post guild_gear_request_path(guild), params: {
          user_id: target_user.id
        }
        
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.not_authorized"))
      end

      it 'cannot bulk request gear updates' do
        expect {
          post guild_gear_request_bulk_path(guild), params: { status: "missing" }
        }.not_to change(GearUploadRequest, :count)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.not_authorized"))
      end
    end

    context 'when user has custom role with gear request permission' do
      let(:officer_user) do
        u = create(:user)
        u.update!(auth_method: "discord")
        u
      end

      before do
        guild.update!(permission_role_1_id: "gear-role-1", role_1_can_manage_gear_requests: true)
        guild.guild_members.create!(user: officer_user, role: :member, status: :active, discord_role_id: "gear-role-1")
        sign_in officer_user
      end

      it 'can request gear updates' do
        GearUploadRequest.where(guild: guild, target_user: target_user).delete_all
        post guild_gear_request_path(guild), params: { user_id: target_user.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /guilds/:id/members_gear support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }
    # Member with **Upgraded** + Discord auth — same shape as **`pending request banner`** examples (`members_gear` requires **`plan_allows?(:ai_gear_scanner)`**).
    let(:gear_member) do
      create(:user).tap { |u| u.update!(auth_method: "discord") }
    end
    let(:upgraded_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
        create(:pricing_plan,
          name: "Upgraded",
          price: 16,
          price_display: "$16",
          period: "per month",
          max_guilds: nil,
          max_members_per_guild: nil,
          active: true,
          display_order: 97)
    end

    before do
      user.subscribe_to_plan!(upgraded_plan)
      gear_member.subscribe_to_plan!(upgraded_plan)
      guild.guild_members.find_or_create_by!(user: gear_member) { |m| m.status = :active; m.role = :member }
      sign_in gear_member
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "redirects gear_upload_success into a clean URL and shows upload success in the toast flash host" do
      get guild_members_gear_path(guild, gear_upload_success: "1", status: "up_to_date")
      expect(response).to redirect_to(guild_members_gear_path(guild, status: "up_to_date"))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      msg = I18n.t("guilds.members_gear.upload_success_notice")
      expect(response.body).to include(Rack::Utils.escape_html(msg))
    end

    it "includes default support URL in HTML" do
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_members_gear_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://members-gear-support.example/help")
      get guild_members_gear_path(guild)
      expect(response.body).to include("https://members-gear-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://members-gear-support.example/help")
      get guild_members_gear_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://members-gear-support.example/help")
    end
  end

  describe "GET /guilds/:id/members_gear last activity display" do
    include ActiveSupport::Testing::TimeHelpers

    let(:roster_member) do
      create(:user).tap { |u| u.update!(auth_method: "discord") }
    end
    let(:upgraded_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
        create(:pricing_plan,
          name: "Upgraded",
          price: 16,
          price_display: "$16",
          period: "per month",
          max_guilds: nil,
          max_members_per_guild: nil,
          active: true,
          display_order: 97)
    end

    before do
      user.subscribe_to_plan!(upgraded_plan)
      roster_member.subscribe_to_plan!(upgraded_plan)
      guild.guild_members.find_or_create_by!(user: roster_member) do |m|
        m.status = :active
        m.role = :member
      end
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "shows per-member last updated using max(created_at, updated_at)" do
      travel_to Time.zone.parse("2026-04-16 15:00:00") do
        snap = create(:gear_snapshot,
          guild: guild,
          user: roster_member,
          game: game,
          data: { "Gear Score" => "1" })
        snap.update_columns(created_at: 30.days.ago, updated_at: Time.current)

        get guild_members_gear_path(guild)

        expect(response).to have_http_status(:ok)
        fragment = ApplicationController.helpers.time_ago_in_words(Time.current)
        expect(response.body).to include(fragment)
      end
    end
  end

  describe "GET /guilds/:id/members_gear pending request banner" do
    let(:target_user) do
      create(:user).tap { |u| u.update!(auth_method: "discord") }
    end

    let(:upgraded_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
        create(:pricing_plan,
          name: "Upgraded",
          price: 16,
          price_display: "$16",
          period: "per month",
          max_guilds: nil,
          max_members_per_guild: nil,
          active: true,
          display_order: 97)
    end

    before do
      user.subscribe_to_plan!(upgraded_plan)
      target_user.subscribe_to_plan!(upgraded_plan)
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    end

    it "shows translated banner when the member has a pending gear upload request" do
      create(:gear_upload_request,
        guild: guild,
        requester: user,
        target_user: target_user,
        status: :pending)
      sign_in target_user
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        I18n.t("guilds.members_gear.pending_request_officer_banner", requester: user.display_name)
      )
    end

    it "does not show the banner copy when there is no pending request for the member" do
      sign_in target_user
      get guild_members_gear_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(
        I18n.t("guilds.members_gear.pending_request_officer_banner", requester: user.display_name)
      )
    end
  end
end

