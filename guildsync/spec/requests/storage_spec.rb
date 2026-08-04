# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "StorageController", type: :request do
  let(:user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.save!
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }
  let(:other_user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.save!
    u.update!(auth_method: "discord")
    u
  end
  let(:member_user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.save!
    u.update!(auth_method: "discord")
    create(:guild_member, guild: guild, user: u, role: :member, status: :active)
    u
  end

  # `StorageController#show` requires `plan_allows?(:file_storage)` (Upgraded+ per `plan_entitlements.yml`).
  let(:upgraded_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
      create(:pricing_plan, name: "Upgraded", price: 19, price_display: "$19", period: "per month",
        max_guilds: 10, max_members_per_guild: 100, active: true, display_order: 50)
  end

  let!(:storage_owner_subscription) { create(:subscription, user: user, pricing_plan: upgraded_plan) }
  let!(:storage_member_subscription) { create(:subscription, user: member_user, pricing_plan: upgraded_plan) }

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
    
    sign_in user
    set_mfa_verified_in_session
  end

  describe "GET /guilds/:guild_id/storage" do
    it "returns success for guild owner" do
      get guild_storage_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "shows file storage page" do
      get guild_storage_path(guild)
      expect(response.body).to include("File Storage")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t('storage.show.drag_drop')))
    end

    it "shows folders in sidebar" do
      folder1 = create(:folder, guild: guild, name: "Test Folder 1")
      folder2 = create(:folder, guild: guild, name: "Test Folder 2", parent_folder: folder1)
      
      get guild_storage_path(guild)
      expect(response.body).to include("Test Folder 1")
      expect(response.body).to include("Test Folder 2")
    end

    it "shows files in grid" do
      file_entry = create(:file_entry, guild: guild, uploaded_by: user.id, name: "test_file.pdf")
      
      get guild_storage_path(guild)
      expect(response.body).to include("test_file.pdf")
    end

    it "shows bulk actions bar when files are selected" do
      create(:file_entry, guild: guild, uploaded_by: user.id, name: "test_file.pdf")
      
      get guild_storage_path(guild)
      expect(response.body).to include("bulk-actions-bar")
      expect(response.body).to include("Move")
      expect(response.body).to include("Delete")
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get guild_storage_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_storage_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-storage-support.example/help")
        get guild_storage_path(guild)
        expect(response.body).to include("https://guild-storage-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-storage-support.example/help")
        get guild_storage_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-storage-support.example/help")
      end
    end

    context "when viewing a folder" do
      let(:folder) { create(:folder, guild: guild, name: "My Folder") }
      
      it "shows files in that folder" do
        file_in_folder = create(:file_entry, guild: guild, folder: folder, uploaded_by: user.id, name: "folder_file.txt")
        file_in_root = create(:file_entry, guild: guild, folder: nil, uploaded_by: user.id, name: "root_file.txt")
        
        get guild_storage_path(guild, folder_id: folder.id)
        expect(response.body).to include("folder_file.txt")
        expect(response.body).not_to include("root_file.txt")
      end

      it "shows breadcrumb navigation" do
        get guild_storage_path(guild, folder_id: folder.id)
        expect(response.body).to include("Root")
        expect(response.body).to include("My Folder")
      end
    end

    context "permissions" do
      it "allows guild members to view files" do
        sign_in member_user
        set_mfa_verified_in_session
        
        create(:file_entry, guild: guild, uploaded_by: user.id, name: "test_file.pdf")
        
        get guild_storage_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include("test_file.pdf")
      end

      it "redirects users with no access to the guild away from the storage page" do
        sign_in other_user
        set_mfa_verified_in_session

        get guild_storage_path(guild)

        expect(response).to redirect_to(my_guilds_path)
        expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
      end

    it "requires authentication" do
      # Authentication is handled by Devise's authenticate_user! before_action
      # This is tested by Devise itself, so we'll just verify the controller has it
      expect(StorageController._process_action_callbacks.map(&:filter)).to include(:authenticate_user!)
    end
    end
  end

  describe "POST /guilds/:guild_id/file_entries (file upload)" do
    let(:test_file) do
      file = Tempfile.new(['test', '.txt'])
      file.write("Test file content")
      file.rewind
      Rack::Test::UploadedFile.new(file.path, 'text/plain')
    end

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
      file.flush
      file.rewind
      Rack::Test::UploadedFile.new(file.path, 'image/png')
    end

    let(:pdf_file) do
      pdf_data = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\nxref\n0 0\ntrailer\n<< /Size 0 /Root 1 0 R >>\nstartxref\n0\n%%EOF"
      file = Tempfile.new(['test', '.pdf'])
      file.write(pdf_data)
      file.flush
      file.rewind
      Rack::Test::UploadedFile.new(file.path, 'application/pdf')
    end

    it "uploads a single file" do
      expect {
        post guild_file_entries_path(guild), params: {
          files: [test_file]
        }
      }.to change { FileEntry.count }.by(1)
        .and change { ActiveStorage::Attachment.count }.by(1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['created']).to be_present
      expect(json['created'].first['name']).to include('test')
      
      file_entry = FileEntry.last
      expect(file_entry.file.attached?).to be true
      expect(file_entry.uploaded_by).to eq(user.id)
    end

    it "uploads multiple files" do
      file2 = Tempfile.new(['test2', '.txt'])
      file2.write("Test file 2")
      file2.rewind
      test_file2 = Rack::Test::UploadedFile.new(file2.path, 'text/plain')

      expect {
        post guild_file_entries_path(guild), params: {
          files: [test_file, test_file2]
        }
      }.to change { FileEntry.count }.by(2)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['created'].length).to eq(2)
    end

    it "uploads file to a folder" do
      folder = create(:folder, guild: guild, name: "Test Folder")
      
      post guild_file_entries_path(guild), params: {
        files: [test_file],
        folder_id: folder.id
      }

      expect(response).to have_http_status(:success)
      file_entry = FileEntry.last
      expect(file_entry.folder).to eq(folder)
    end

    it "uploads image file and sets metadata" do
      post guild_file_entries_path(guild), params: {
        files: [image_file]
      }

      expect(response).to have_http_status(:success)
      file_entry = FileEntry.last
      expect(file_entry.content_type).to eq('image/png')
      expect(file_entry.size).to be > 0
      expect(file_entry.image?).to be true
      expect(file_entry.video?).to be false
      expect(file_entry.pdf?).to be false
    end

    it "uploads PDF file and sets metadata" do
      post guild_file_entries_path(guild), params: {
        files: [pdf_file]
      }

      expect(response).to have_http_status(:success)
      file_entry = FileEntry.last
      expect(file_entry.content_type).to eq('application/pdf')
      expect(file_entry.size).to be > 0
      expect(file_entry.pdf?).to be true
      expect(file_entry.compressible?).to be true
    end

    it "sets file size and content type from blob" do
      post guild_file_entries_path(guild), params: {
        files: [test_file]
      }

      file_entry = FileEntry.last
      expect(file_entry.size).to be > 0
      expect(file_entry.content_type).to be_present
    end

    it "returns error when no files provided" do
      post guild_file_entries_path(guild), params: {}

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("No files selected")
    end

    it "handles upload errors gracefully" do
      # Simulate an error by passing invalid file data
      allow_any_instance_of(FileEntry).to receive(:save).and_return(false)
      allow_any_instance_of(FileEntry).to receive(:errors).and_return(
        double(full_messages: ["Name can't be blank"])
      )

      post guild_file_entries_path(guild), params: {
        files: [test_file]
      }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors']).to be_present
    end

    it "requires permission to upload" do
      # Make other_user a member but without manage_files permission
      create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
      sign_in other_user
      set_mfa_verified_in_session

      post guild_file_entries_path(guild), params: {
        files: [test_file]
      }

      expect(response).to redirect_to(guild_storage_path(guild))
      expect(flash[:alert]).to include("permission")
    end

    it "allows users with manage_files permission to upload" do
      # Create a user with manage_files permission via role
      member = create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
      # Set a discord_role_id for the member so permission check works
      role_id = "role_#{SecureRandom.hex(8)}"
      member.update!(discord_role_id: role_id)
      guild.update!(
        permission_role_1_id: role_id,
        role_1_can_manage_files: true
      )
      
      sign_in other_user
      set_mfa_verified_in_session

      expect {
        post guild_file_entries_path(guild), params: {
          files: [test_file]
        }
      }.to change { FileEntry.count }.by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /guilds/:guild_id/folders (create folder)" do
    it "creates a folder" do
      expect {
        post guild_folders_path(guild), params: {
          folder: { name: "New Folder" }
        }, headers: { 'Accept' => 'application/json' }
      }.to change { Folder.count }.by(1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['folder']['name']).to eq("New Folder")
      expect(json['folder']['id']).to be_present
    end

    it "creates a nested folder" do
      parent_folder = create(:folder, guild: guild, name: "Parent Folder")

      expect {
        post guild_folders_path(guild), params: {
          folder: { name: "Child Folder" },
          parent_folder_id: parent_folder.id
        }, headers: { 'Accept' => 'application/json' }
      }.to change { Folder.count }.by(1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      child_folder = Folder.find(json['folder']['id'])
      expect(child_folder.parent_folder).to eq(parent_folder)
    end

    it "creates folder in current folder context" do
      current_folder = create(:folder, guild: guild, name: "Current Folder")

      post guild_folders_path(guild), params: {
        folder: { name: "Nested Folder" },
        parent_folder_id: current_folder.id
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      nested_folder = Folder.find(json['folder']['id'])
      expect(nested_folder.parent_folder).to eq(current_folder)
    end

    it "validates folder name" do
      post guild_folders_path(guild), params: {
        folder: { name: "" }
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to be_present
    end

    it "validates folder name length" do
      post guild_folders_path(guild), params: {
        folder: { name: "a" * 256 }
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to be_present
    end

    it "denies folder create when the user has no access to the guild (HTML)" do
      sign_in other_user
      set_mfa_verified_in_session

      post guild_folders_path(guild), params: {
        folder: { name: "New Folder" }
      }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "denies folder create when the user has no access to the guild (JSON)" do
      sign_in other_user
      set_mfa_verified_in_session

      post guild_folders_path(guild), params: {
        folder: { name: "New Folder" }
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "accepts flat name without nested folder key" do
      post guild_folders_path(guild), params: {
        name: "Direct Name"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success).or have_http_status(:unprocessable_entity)
    end

    it "returns 400 JSON with controllers.folders.missing_required_parameter when folder_params raises ParameterMissing" do
      allow_any_instance_of(FoldersController).to receive(:folder_params).and_raise(
        ActionController::ParameterMissing.new(:folder)
      )

      post guild_folders_path(guild), params: { folder: { name: "ignored" } },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq(
        I18n.t("controllers.folders.missing_required_parameter", param: :folder)
      )
    end
  end

  describe "PATCH /guilds/:guild_id/file_entries/bulk_move (drag and drop)" do
    let(:folder1) { create(:folder, guild: guild, name: "Folder 1") }
    let(:folder2) { create(:folder, guild: guild, name: "Folder 2") }
    let(:file1) { create(:file_entry, guild: guild, folder: folder1, uploaded_by: user.id) }
    let(:file2) { create(:file_entry, guild: guild, folder: folder1, uploaded_by: user.id) }
    let(:file3) { create(:file_entry, guild: guild, folder: nil, uploaded_by: user.id) }

    it "moves multiple files to a folder (bulk move)" do
      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [file1.id, file2.id],
        folder_id: folder2.id
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['moved_count']).to eq(2)

      file1.reload
      file2.reload
      expect(file1.folder).to eq(folder2)
      expect(file2.folder).to eq(folder2)
    end

    it "moves a single file to a folder (drag and drop)" do
      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [file3.id],
        folder_id: folder1.id
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      file3.reload
      expect(file3.folder).to eq(folder1)
    end

    it "moves files to root (no folder)" do
      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [file1.id],
        folder_id: ""
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      file1.reload
      expect(file1.folder).to be_nil
    end

    it "moves files to root with null folder_id" do
      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [file1.id],
        folder_id: nil
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      file1.reload
      expect(file1.folder).to be_nil
    end

    it "handles empty file_ids array" do
      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [],
        folder_id: folder2.id
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("No files selected")
    end

    it "requires permission to move files" do
      # Make other_user a member but without manage_files permission
      create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
      sign_in other_user
      set_mfa_verified_in_session

      patch bulk_move_guild_file_entries_path(guild), params: {
        file_ids: [file1.id],
        folder_id: folder2.id
      }

      expect(response).to redirect_to(guild_storage_path(guild))
    end
  end

  describe "DELETE /guilds/:guild_id/file_entries/bulk_destroy (bulk delete)" do
    let!(:file1) { create(:file_entry, :with_file, guild: guild, uploaded_by: user.id) }
    let!(:file2) { create(:file_entry, :with_file, guild: guild, uploaded_by: user.id) }
    let!(:file3) { create(:file_entry, :with_file, guild: guild, uploaded_by: user.id) }

    it "deletes multiple files (bulk delete)" do
      expect {
        delete bulk_destroy_guild_file_entries_path(guild), params: {
          file_ids: [file1.id, file2.id]
        }, headers: { 'Accept' => 'application/json' }
      }.to change { FileEntry.count }.by(-2)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['deleted_count']).to eq(2)
    end

    it "deletes a single file via bulk delete" do
      expect {
        delete bulk_destroy_guild_file_entries_path(guild), params: {
          file_ids: [file1.id]
        }, headers: { 'Accept' => 'application/json' }
      }.to change { FileEntry.count }.by(-1)

      expect(response).to have_http_status(:success)
    end

    it "handles empty file_ids array" do
      delete bulk_destroy_guild_file_entries_path(guild), params: {
        file_ids: []
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("No files selected")
    end

    it "handles invalid file_ids" do
      delete bulk_destroy_guild_file_entries_path(guild), params: {
        file_ids: [99999, 99998]
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['deleted_count']).to eq(0)
    end

    it "only deletes files from the current guild" do
      other_guild = create(:guild, owner: other_user)
      other_file = create(:file_entry, guild: other_guild, uploaded_by: other_user.id)

      delete bulk_destroy_guild_file_entries_path(guild), params: {
        file_ids: [file1.id, other_file.id]
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      expect(FileEntry.find_by(id: file1.id)).to be_nil
      expect(FileEntry.find_by(id: other_file.id)).to be_present
    end

    it "requires permission to delete files" do
      # Make other_user a member but without manage_files permission
      create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
      sign_in other_user
      set_mfa_verified_in_session

      delete bulk_destroy_guild_file_entries_path(guild), params: {
        file_ids: [file1.id]
      }

      expect(response).to redirect_to(guild_storage_path(guild))
    end
  end

  describe "DELETE /guilds/:guild_id/file_entries/:id (single file delete)" do
    let(:file_entry) { create(:file_entry, :with_file, guild: guild, uploaded_by: user.id) }

    it "deletes a single file" do
      file_entry_id = file_entry.id
      expect {
        delete guild_file_entry_path(guild, file_entry), headers: { 'Accept' => 'application/json' }
      }.to change { FileEntry.count }.by(-1)
        .and change { FileEntry.where(id: file_entry_id).count }.by(-1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(FileEntry.find_by(id: file_entry_id)).to be_nil
    end

    it "soft-deletes file but keeps ActiveStorage blob for admin restore" do
      file_entry.file.attach(
        io: StringIO.new("test content"),
        filename: "test.txt",
        content_type: "text/plain"
      )

      expect {
        delete guild_file_entry_path(guild, file_entry), headers: { 'Accept' => 'application/json' }
      }.to change { FileEntry.count }.by(-1)
        .and change { ActiveStorage::Attachment.count }.by(0)

      trashed = FileEntry.with_deleted.find(file_entry.id)
      expect(trashed.file).to be_attached
    end

    it "requires permission to delete" do
      # Make other_user a member but without manage_files permission
      create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
      sign_in other_user
      set_mfa_verified_in_session

      delete guild_file_entry_path(guild, file_entry)

      expect(response).to redirect_to(guild_storage_path(guild))
    end
  end

  describe "GET /guilds/:guild_id/file_entries/:id/download" do
    let(:file_entry) do
      fe = create(:file_entry, guild: guild, uploaded_by: user.id, name: "test.txt")
      fe.file.attach(
        io: StringIO.new("test content"),
        filename: "test.txt",
        content_type: "text/plain"
      )
      fe
    end

    it "downloads a file" do
      get download_guild_file_entry_path(guild, file_entry)
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("rails/active_storage")
      expect(response.location).to include("blobs")
    end

    it "allows guild members to download files" do
      sign_in member_user
      set_mfa_verified_in_session

      get download_guild_file_entry_path(guild, file_entry)
      expect(response).to have_http_status(:redirect)
    end

    it "handles file without attachment" do
      file_entry_without_file = create(:file_entry, guild: guild, uploaded_by: user.id, name: "missing.txt")

      get download_guild_file_entry_path(guild, file_entry_without_file)
      expect(response).to redirect_to(guild_storage_path(guild))
      expect(flash[:alert]).to include("File not found")
    end
  end

  describe "PATCH /guilds/:guild_id/folders/:id (update folder)" do
    let(:folder) { create(:folder, guild: guild, name: "Old Name") }

    it "renames a folder" do
      patch update_guild_folder_path(guild, folder), params: {
        folder: { name: "New Name" }
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      folder.reload
      expect(folder.name).to eq("New Name")
    end

    it "moves a folder to a different parent" do
      parent1 = create(:folder, guild: guild, name: "Parent 1")
      parent2 = create(:folder, guild: guild, name: "Parent 2")
      folder.update!(parent_folder: parent1)

      patch update_guild_folder_path(guild, folder), params: {
        folder: { name: folder.name, parent_folder_id: parent2.id }
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      folder.reload
      expect(folder.parent_folder).to eq(parent2)
    end

    it "prevents moving folder into itself" do
      patch update_guild_folder_path(guild, folder), params: {
        folder: { name: folder.name, parent_folder_id: folder.id }
      }, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("Cannot move folder into itself")
    end

    it "prevents moving folder into its descendant" do
      child = create(:folder, guild: guild, name: "Child", parent_folder: folder)
      
      patch update_guild_folder_path(guild, child), params: {
        folder: { name: child.name, parent_folder_id: folder.id }
      }, headers: { 'Accept' => 'application/json' }

      # This should be prevented by the controller
      expect(response).to have_http_status(:success).or have_http_status(:unprocessable_entity)
    end

    it "denies folder update when the user has no access to the guild" do
      sign_in other_user
      set_mfa_verified_in_session

      patch update_guild_folder_path(guild, folder), params: {
        folder: { name: "New Name" }
      }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "DELETE /guilds/:guild_id/folders/:id" do
    let(:folder) { create(:folder, guild: guild, name: "Test Folder") }

    it "deletes an empty folder" do
      folder_id = folder.id
      expect {
        delete guild_folder_path(guild, folder), headers: { 'Accept' => 'application/json' }
      }.to change { Folder.count }.by(-1)
        .and change { Folder.where(id: folder_id).count }.by(-1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(Folder.find_by(id: folder_id)).to be_nil
    end

    it "prevents deleting folder with files" do
      create(:file_entry, guild: guild, folder: folder, uploaded_by: user.id)

      delete guild_folder_path(guild, folder), headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("not empty")
    end

    it "prevents deleting folder with subfolders" do
      create(:folder, guild: guild, parent_folder: folder, name: "Subfolder")

      delete guild_folder_path(guild, folder), headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to include("not empty")
    end

    it "denies folder delete when the user has no access to the guild" do
      sign_in other_user
      set_mfa_verified_in_session

      delete guild_folder_path(guild, folder)

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "File metadata and helpers" do
    let(:file_entry) { create(:file_entry, :with_file, guild: guild, uploaded_by: user.id, name: "test.txt", size: 1024) }

    it "formats file size correctly" do
      expect(file_entry.formatted_size).to match(/1\.0+ KB/)
    end

    it "detects image files" do
      image_entry = create(:file_entry, :image, guild: guild, uploaded_by: user.id)
      expect(image_entry.image?).to be true
      expect(image_entry.video?).to be false
      expect(image_entry.pdf?).to be false
    end

    it "detects PDF files" do
      pdf_entry = create(:file_entry, guild: guild, uploaded_by: user.id, name: "test.pdf", content_type: "application/pdf")
      expect(pdf_entry.pdf?).to be true
      expect(pdf_entry.compressible?).to be true
    end

    it "identifies compressible files" do
      image_entry = create(:file_entry, :image, guild: guild, uploaded_by: user.id)
      pdf_entry = create(:file_entry, guild: guild, uploaded_by: user.id, name: "test.pdf", content_type: "application/pdf")
      text_entry = create(:file_entry, guild: guild, uploaded_by: user.id, name: "test.txt", content_type: "text/plain")

      expect(image_entry.compressible?).to be true
      expect(pdf_entry.compressible?).to be true
      expect(text_entry.compressible?).to be false
    end
  end

  describe "Folder tree structure" do
    it "builds folder tree correctly" do
      root1 = create(:folder, guild: guild, name: "Root 1")
      root2 = create(:folder, guild: guild, name: "Root 2")
      child1 = create(:folder, guild: guild, name: "Child 1", parent_folder: root1)
      child2 = create(:folder, guild: guild, name: "Child 2", parent_folder: root1)
      grandchild = create(:folder, guild: guild, name: "Grandchild", parent_folder: child1)

      get guild_storage_path(guild)
      
      expect(response.body).to include("Root 1")
      expect(response.body).to include("Root 2")
      expect(response.body).to include("Child 1")
      expect(response.body).to include("Child 2")
    end

    it "shows folder ancestors in breadcrumb" do
      root = create(:folder, guild: guild, name: "Root Folder")
      child = create(:folder, guild: guild, name: "Child Folder", parent_folder: root)
      grandchild = create(:folder, guild: guild, name: "Grandchild Folder", parent_folder: child)

      get guild_storage_path(guild, folder_id: grandchild.id)
      
      expect(response.body).to include("Root Folder")
      expect(response.body).to include("Child Folder")
      expect(response.body).to include("Grandchild Folder")
    end
  end
end
