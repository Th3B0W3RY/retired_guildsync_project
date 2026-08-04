# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GuildDocumentsController", type: :request do
  include ActionDispatch::TestProcess
  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }
  let(:other_user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:member_user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    create(:guild_member, guild: guild, user: u, role: :member, status: :active)
    u
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

  def subscribe_upgraded!(u)
    u.subscribe_to_plan!(upgraded_plan)
  end

  before do
    subscribe_upgraded!(user)
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "GET /guilds/:guild_id/documents" do
    context "with permission" do
      it "returns success" do
        get guild_documents_path(guild)
        expect(response).to have_http_status(:success)
      end

      it "lists documents" do
        doc1 = create(:guild_document, guild: guild, user: user, visibility: :public_doc)
        doc2 = create(:guild_document, guild: guild, user: user, visibility: :private_doc)
        
        get guild_documents_path(guild)
        expect(response.body).to include(doc1.title)
        expect(response.body).to include(doc2.title)
      end

      it "shows unlisted documents to users with manage permission" do
        doc = create(:guild_document, guild: guild, user: user, visibility: :unlisted_doc)
        
        get guild_documents_path(guild)
        expect(response.body).to include(doc.title)
      end

      describe "support_center_url in member chrome" do
        let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

        it "includes default support URL in HTML" do
          get guild_documents_path(guild)
          expect(response).to have_http_status(:success)
          expect(response.body).to include(default_support_url)
        end

        it "includes default support URL on mobile variant" do
          get guild_documents_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
          expect(response).to have_http_status(:success)
          expect(response.body).to include(default_support_url)
        end

        it "includes configured custom support URL when set" do
          SiteSetting.set("release_notes_url", "https://guild-documents-support.example/help")
          get guild_documents_path(guild)
          expect(response.body).to include("https://guild-documents-support.example/help")
        end

        it "includes configured custom support URL on mobile variant when set" do
          SiteSetting.set("release_notes_url", "https://guild-documents-support.example/help")
          get guild_documents_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
          expect(response.body).to include("https://guild-documents-support.example/help")
        end
      end
    end

    context "without permission" do
      before do
        subscribe_upgraded!(other_user)
        sign_in other_user
        set_mfa_verified_in_session
      end

      it "shows only documents user can view" do
        public_doc = create(:guild_document, guild: guild, user: user, visibility: :public_doc)
        private_doc = create(:guild_document, guild: guild, user: user, visibility: :private_doc)
        
        get guild_documents_path(guild)
        expect(response).to have_http_status(:success)
        # Should see public doc but not private doc
        expect(response.body).to include(public_doc.title)
        expect(response.body).not_to include(private_doc.title)
      end
    end
  end

  describe "GET /guilds/:guild_id/documents/new" do
    it "returns success for guild owner" do
      get new_guild_document_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "redirects without permission" do
      subscribe_upgraded!(other_user)
      sign_in other_user
      set_mfa_verified_in_session

      get new_guild_document_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get new_guild_document_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get new_guild_document_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-new-support.example/help")
        get new_guild_document_path(guild)
        expect(response.body).to include("https://guild-documents-new-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-new-support.example/help")
        get new_guild_document_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-documents-new-support.example/help")
      end
    end
  end

  describe "POST /guilds/:guild_id/documents" do
    let(:valid_params) do
      {
        guild_document: {
          title: "Test Document",
          visibility: "public_doc",
          content: { type: "doc", content: [] }
        }
      }
    end

    it "creates document" do
      expect {
        post guild_documents_path(guild), params: valid_params
      }.to change(GuildDocument, :count).by(1)
    end

    it "redirects to documents index" do
      post guild_documents_path(guild), params: valid_params
      expect(response).to redirect_to(guild_documents_path(guild))
    end

    it "generates slug automatically" do
      post guild_documents_path(guild), params: valid_params
      document = GuildDocument.last
      expect(document.slug).to be_present
      expect(document.slug).to include("test-document")
    end

    context "with invalid params" do
      it "renders new with errors" do
        post guild_documents_path(guild), params: { guild_document: { title: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Title")
      end
    end
  end

  describe "POST /guilds/:guild_id/documents/upload_image" do
    let(:png_file) { fixture_file_upload(Rails.root.join("spec/fixtures/files/dot.png"), "image/png") }

    it "returns 200 and JSON with url when image is provided" do
      post upload_image_guild_documents_path(guild), params: { image: png_file }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("url")
      expect(json["url"]).to be_present
    end

    it "returns 422 when image is missing" do
      post upload_image_guild_documents_path(guild), params: {}
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json).to have_key("error")
    end
  end

  describe "GET /guilds/:guild_id/documents/:id" do
    let(:document) { create(:guild_document, guild: guild, user: user) }

    it "returns success for guild member" do
      get guild_document_path(guild, document)
      expect(response).to have_http_status(:success)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get guild_document_path(guild, document)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_document_path(guild, document), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-show-support.example/help")
        get guild_document_path(guild, document)
        expect(response.body).to include("https://guild-documents-show-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-show-support.example/help")
        get guild_document_path(guild, document), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-documents-show-support.example/help")
      end
    end

    context "with private document" do
      let(:document) { create(:guild_document, guild: guild, user: user, visibility: :private_doc) }

      it "allows guild members to view" do
        subscribe_upgraded!(member_user)
        sign_in member_user
        set_mfa_verified_in_session

        get guild_document_path(guild, document)
        expect(response).to have_http_status(:success)
      end

      it "blocks non-members" do
        subscribe_upgraded!(other_user)
        sign_in other_user
        set_mfa_verified_in_session

        get guild_document_path(guild, document)
        expect(response).to redirect_to(guild_path(guild))
      end
    end

    context "with public document" do
      let(:document) { create(:guild_document, guild: guild, user: user, visibility: :public_doc) }

      it "allows anyone to view" do
        # Public documents should be viewable even without authentication
        get guild_document_path(guild, document)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /guilds/:guild_id/documents/:id/share" do
    let(:document) { create(:guild_document, guild: guild, user: user, visibility: :public_doc) }

    it "returns success for public document" do
      get share_guild_document_path(guild, document, slug: document.slug)
      expect(response).to have_http_status(:success)
    end

    it "requires correct slug" do
      get share_guild_document_path(guild, document, slug: "wrong-slug")
      # Should redirect if slug doesn't match
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("Invalid document link")
    end

    context "with private document" do
      let(:document) { create(:guild_document, guild: guild, user: user, visibility: :private_doc) }

      it "requires authentication and membership" do
        # User from before block is the guild owner, so they ARE a member
        # Test with a non-member user instead
        sign_out user
        sign_in other_user
        set_mfa_verified_in_session
        
        get share_guild_document_path(guild, document, slug: document.slug)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("private")
      end
      
      context "when not signed in" do
        before do
          # Clear the session to ensure no user is authenticated
          # The share action skips authenticate_user!, so we need to ensure current_user is nil
          allow_any_instance_of(GuildDocumentsController).to receive(:current_user).and_return(nil)
        end

        it "requires authentication" do
          get share_guild_document_path(guild, document, slug: document.slug)
          # Should redirect because private documents require authentication
          expect(response).to redirect_to(root_path)
          follow_redirect! if response.redirect?
          expect(flash[:alert]).to include("private") if flash[:alert]
        end
      end
      
      it "allows guild members" do
        sign_in member_user
        set_mfa_verified_in_session
        
        get share_guild_document_path(guild, document, slug: document.slug)
        expect(response).to have_http_status(:success)
      end
    end

    context "with unlisted document" do
      let(:document) { create(:guild_document, guild: guild, user: user, visibility: :unlisted_doc) }

      it "allows access via link" do
        get share_guild_document_path(guild, document, slug: document.slug)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /guilds/:guild_id/documents/:id/edit" do
    let(:document) { create(:guild_document, guild: guild, user: user) }

    it "returns success for guild owner" do
      get edit_guild_document_path(guild, document)
      expect(response).to have_http_status(:success)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get edit_guild_document_path(guild, document)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get edit_guild_document_path(guild, document), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-edit-support.example/help")
        get edit_guild_document_path(guild, document)
        expect(response.body).to include("https://guild-documents-edit-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-documents-edit-support.example/help")
        get edit_guild_document_path(guild, document), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-documents-edit-support.example/help")
      end
    end
  end

  describe "PATCH /guilds/:guild_id/documents/:id" do
    let(:document) { create(:guild_document, guild: guild, user: user) }

    it "updates document" do
      patch guild_document_path(guild, document), params: {
        guild_document: { 
          title: "Updated Title",
          visibility: document.visibility
        }
      }
      expect(document.reload.title).to eq("Updated Title")
    end

    it "allows document creator to edit" do
      patch guild_document_path(guild, document), params: {
        guild_document: { 
          title: "Updated by Creator",
          visibility: document.visibility
        }
      }
      expect(response).to redirect_to(guild_document_path(guild, document))
    end

    it "allows guild owner to edit" do
      other_doc = create(:guild_document, guild: guild, user: other_user)
      patch guild_document_path(guild, other_doc), params: {
        guild_document: { 
          title: "Updated by Owner",
          visibility: other_doc.visibility
        }
      }
      expect(response).to redirect_to(guild_document_path(guild, other_doc))
    end

    it "blocks non-authorized users" do
      subscribe_upgraded!(other_user)
      sign_in other_user
      set_mfa_verified_in_session

      patch guild_document_path(guild, document), params: {
        guild_document: { title: "Hacked" }
      }
      expect(response).to redirect_to(guild_path(guild))
    end
  end

  describe "DELETE /guilds/:guild_id/documents/:id" do
    let!(:document) { create(:guild_document, guild: guild, user: user) }

    it "deletes document" do
      expect {
        delete guild_document_path(guild, document)
      }.to change(GuildDocument, :count).by(-1)
    end

    it "redirects to documents index" do
      delete guild_document_path(guild, document)
      expect(response).to redirect_to(guild_documents_path(guild))
    end
  end

  describe "POST /guilds/:guild_id/documents/autosave" do
    it "creates new document for autosave" do
      expect {
        post autosave_guild_documents_path(guild), params: {
          title: "Autosave Test",
          content: { type: "doc", content: [] }.to_json
        }
      }.to change(GuildDocument, :count).by(1)
    end

    it "updates existing document" do
      document = create(:guild_document, guild: guild, user: user)
      new_content = { type: "doc", content: [{ type: "paragraph", content: [] }] }
      
      post autosave_guild_documents_path(guild), params: {
        id: document.id,
        content: new_content.to_json
      }
      
      document.reload
      # Content is stored as JSON, so keys will be strings
      expect(document.content).to eq(new_content.deep_stringify_keys)
    end

    it "returns JSON response" do
      post autosave_guild_documents_path(guild), params: {
        title: "Test",
        content: {}.to_json
      }
      
      expect(response.content_type).to include("application/json")
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["id"]).to be_present
    end

    it "returns localized forbidden when officer can manage documents but cannot edit another user's document" do
      permission_role_id = "discord-role-docs-autosave-1"
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_documents: true
      )
      officer = create(:user, auth_method: "discord")
      subscribe_upgraded!(officer)
      create(:guild_member, guild: guild, user: officer, role: :member, status: :active,
        discord_role_id: permission_role_id)
      document = create(:guild_document, guild: guild, user: user, visibility: :private_doc)

      sign_in officer
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      post autosave_guild_documents_path(guild), params: {
        id: document.id,
        content: { type: "doc", content: [] }.to_json
      }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.not_authorized"))
    end
  end

  describe "POST /guilds/:guild_id/documents with content as JSON string" do
    it "parses JSON string content correctly" do
      content_json = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "Test content" }] }] }.to_json
      
      post guild_documents_path(guild), params: {
        guild_document: {
          title: "JSON Content Test",
          visibility: "public_doc",
          content: content_json
        }
      }
      
      document = GuildDocument.last
      expect(document.content).to eq({
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [
              {
                "type" => "text",
                "text" => "Test content"
              }
            ]
          }
        ]
      })
    end

    it "normalizes invalid content to default structure" do
      post guild_documents_path(guild), params: {
        guild_document: {
          title: "Invalid Content Test",
          visibility: "public_doc",
          content: "invalid json string"
        }
      }
      
      document = GuildDocument.last
      expect(document.content).to eq({ "type" => "doc", "content" => [] })
    end

    it "handles content as hash" do
      content_hash = { type: "doc", content: [{ type: "paragraph", content: [] }] }
      
      post guild_documents_path(guild), params: {
        guild_document: {
          title: "Hash Content Test",
          visibility: "public_doc",
          content: content_hash.to_json  # Convert to JSON string to match real behavior
        }
      }
      
      document = GuildDocument.last
      expect(document.content).to eq(content_hash.deep_stringify_keys)
    end
  end

  describe "PATCH /guilds/:guild_id/documents/:id with content updates" do
    let(:document) { create(:guild_document, guild: guild, user: user) }

    it "updates content from JSON string" do
      new_content = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "Updated" }] }] }.to_json
      
      patch guild_document_path(guild, document), params: {
        guild_document: {
          title: document.title,  # Keep existing title
          visibility: document.visibility,  # Keep existing visibility
          content: new_content
        }
      }
      
      document.reload
      expect(document.content["content"].first["content"].first["text"]).to eq("Updated")
    end

    it "normalizes content on update" do
      patch guild_document_path(guild, document), params: {
        guild_document: {
          title: document.title,  # Keep existing title
          visibility: document.visibility,  # Keep existing visibility
          content: "invalid"
        }
      }
      
      document.reload
      expect(document.content).to eq({ "type" => "doc", "content" => [] })
    end
  end

  describe "POST /guilds/:guild_id/documents/create_folder" do
    let(:valid_folder_params) do
      {
        guild_document_folder: {
          name: "Test Folder",
          color: "#3b82f6"
        }
      }
    end

    it "creates a folder" do
      expect {
        post create_folder_guild_documents_path(guild), params: valid_folder_params
      }.to change(GuildDocumentFolder, :count).by(1)
    end

    it "redirects to documents index with notice" do
      post create_folder_guild_documents_path(guild), params: valid_folder_params
      expect(response).to redirect_to(guild_documents_path(guild))
      expect(flash[:notice]).to include("Folder created successfully")
    end

    it "assigns folder to current user" do
      post create_folder_guild_documents_path(guild), params: valid_folder_params
      folder = GuildDocumentFolder.last
      expect(folder.user).to eq(user)
      expect(folder.guild).to eq(guild)
    end

    it "sets position automatically" do
      folder1 = create(:guild_document_folder, guild: guild, position: 0)
      post create_folder_guild_documents_path(guild), params: valid_folder_params
      folder2 = GuildDocumentFolder.last
      expect(folder2.position).to eq(1)
    end

    context "with invalid params" do
      it "redirects with error message" do
        post create_folder_guild_documents_path(guild), params: {
          guild_document_folder: { name: "" }
        }
        expect(response).to redirect_to(guild_documents_path(guild))
        expect(flash[:alert]).to be_present
      end
    end

    context "without permission" do
      before do
        subscribe_upgraded!(other_user)
        sign_in other_user
        set_mfa_verified_in_session
      end

      it "redirects without creating folder" do
        expect {
          post create_folder_guild_documents_path(guild), params: valid_folder_params
        }.not_to change(GuildDocumentFolder, :count)
        expect(response).to redirect_to(guild_path(guild))
      end
    end
  end

  describe "PATCH /guilds/:guild_id/documents/update_folder" do
    let!(:folder) { create(:guild_document_folder, guild: guild, user: user, name: "Original Name", color: "#3b82f6") }

    it "updates folder" do
      patch update_folder_guild_documents_path(guild), params: {
        folder_id: folder.id,
        guild_document_folder: {
          name: "Updated Name",
          color: "#ef4444"
        }
      }
      
      folder.reload
      expect(folder.name).to eq("Updated Name")
      expect(folder.color).to eq("#ef4444")
    end

    it "redirects with notice" do
      patch update_folder_guild_documents_path(guild), params: {
        folder_id: folder.id,
        guild_document_folder: { name: "Updated" }
      }
      expect(response).to redirect_to(guild_documents_path(guild))
      expect(flash[:notice]).to include("Folder updated successfully")
    end

    context "without permission" do
      let(:other_folder) { create(:guild_document_folder, guild: guild, user: other_user, name: "Other Folder") }
      let(:member_only_user) do
        u = create(:user)
        u.update!(auth_method: "discord")
        create(:guild_member, guild: guild, user: u, role: :member, status: :active)
        u
      end
      
      before do
        # Sign in as a member who is NOT the guild owner and did NOT create the folder
        subscribe_upgraded!(member_only_user)
        sign_in member_only_user
        set_mfa_verified_in_session
      end

      it "redirects with error" do
        patch update_folder_guild_documents_path(guild), params: {
          folder_id: other_folder.id,
          guild_document_folder: { name: "Hacked" }
        }
        # Member without document management permission gets redirected by check_permissions
        expect(response).to redirect_to(guild_path(guild))
        expect(flash[:alert]).to be_present
        expect(flash[:alert]).to match(/permission/i)
        expect(other_folder.reload.name).to eq("Other Folder")
      end
    end

    context "guild owner" do
      it "can update any folder" do
        other_folder = create(:guild_document_folder, guild: guild, user: other_user, name: "Other Folder")
        patch update_folder_guild_documents_path(guild), params: {
          folder_id: other_folder.id,
          guild_document_folder: { name: "Updated by Owner" }
        }
        expect(other_folder.reload.name).to eq("Updated by Owner")
      end
    end
  end

  describe "DELETE /guilds/:guild_id/documents/destroy_folder" do
    let!(:folder) { create(:guild_document_folder, guild: guild, user: user) }

    it "deletes folder" do
      expect {
        delete destroy_folder_guild_documents_path(guild), params: { folder_id: folder.id }
      }.to change(GuildDocumentFolder, :count).by(-1)
    end

    it "redirects with notice" do
      delete destroy_folder_guild_documents_path(guild), params: { folder_id: folder.id }
      expect(response).to redirect_to(guild_documents_path(guild))
      expect(flash[:notice]).to include("Folder deleted successfully")
    end

    it "nullifies documents in folder" do
      document = create(:guild_document, guild: guild, user: user, folder: folder)
      delete destroy_folder_guild_documents_path(guild), params: { folder_id: folder.id }
      expect(document.reload.folder_id).to be_nil
    end

    context "without permission" do
      let!(:other_folder) { create(:guild_document_folder, guild: guild, user: other_user) }
      let(:member_only_user) do
        u = create(:user)
        u.update!(auth_method: "discord")
        create(:guild_member, guild: guild, user: u, role: :member, status: :active)
        u
      end
      
      before do
        # Sign in as a member who is NOT the guild owner and did NOT create the folder
        subscribe_upgraded!(member_only_user)
        sign_in member_only_user
        set_mfa_verified_in_session
      end

      it "redirects with error" do
        initial_count = GuildDocumentFolder.count
        delete destroy_folder_guild_documents_path(guild), params: { folder_id: other_folder.id }
        # Member without document management permission gets redirected by check_permissions
        expect(response).to redirect_to(guild_path(guild))
        expect(flash[:alert]).to be_present
        expect(flash[:alert]).to match(/permission/i)
        # Folder should not be deleted
        expect(GuildDocumentFolder.count).to eq(initial_count)
        expect(other_folder.reload).to be_present
      end
    end
  end

  describe "Document folder assignment" do
    let!(:folder) { create(:guild_document_folder, guild: guild, user: user) }

    it "creates document with folder" do
      post guild_documents_path(guild), params: {
        guild_document: {
          title: "Document in Folder",
          visibility: "public_doc",
          folder_id: folder.id,
          content: { type: "doc", content: [] }
        }
      }
      
      document = GuildDocument.last
      expect(document.folder).to eq(folder)
    end

    it "updates document folder" do
      document = create(:guild_document, guild: guild, user: user)
      new_folder = create(:guild_document_folder, guild: guild, user: user, name: "New Folder")
      
      patch guild_document_path(guild, document), params: {
        guild_document: {
          title: document.title,  # Keep existing title
          visibility: document.visibility,  # Keep existing visibility
          folder_id: new_folder.id
        }
      }
      
      expect(document.reload.folder).to eq(new_folder)
    end

    it "allows removing folder from document" do
      document = create(:guild_document, guild: guild, user: user, folder: folder)
      
      patch guild_document_path(guild, document), params: {
        guild_document: {
          title: document.title,  # Keep existing title
          visibility: document.visibility,  # Keep existing visibility
          folder_id: nil
        }
      }
      
      expect(document.reload.folder).to be_nil
    end
  end
end
