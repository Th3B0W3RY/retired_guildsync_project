# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin::ContentModeration", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/content_moderation" do
    let(:cm_index) { "admin.content_moderation.index" }

    it "shows content moderation page" do
      get admin_content_moderation_index_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_content_moderation_index_main"))
      expect(response.body).to include(I18n.t("#{cm_index}.page_title"))
    end

    it "renders frame-only body when Turbo-Frame requests index main" do
      get admin_content_moderation_index_path,
        headers: { "Turbo-Frame" => Admin::ContentModerationController::CONTENT_MODERATION_INDEX_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_content_moderation_index_main"))
      expect(response.body).to include(I18n.t("#{cm_index}.tab_pending"))
      expect(response.body).not_to include(I18n.t("#{cm_index}.page_title"))
    end

    it "frame-only GET respects tab param" do
      get admin_content_moderation_index_path(tab: "health"),
        headers: { "Turbo-Frame" => Admin::ContentModerationController::CONTENT_MODERATION_INDEX_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("#{cm_index}.health_heading"))
      expect(response.body).not_to include(I18n.t("#{cm_index}.page_title"))
    end

    it "shows profanity list tab content when tab=profanity_list" do
      create(:profanity_update_log, total_words: 10)
      get admin_content_moderation_index_path(tab: "profanity_list")
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("#{cm_index}.page_title"))
    end

    it "shows blocked words tab when tab=blocked_words" do
      get admin_content_moderation_index_path(tab: "blocked_words")
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("#{cm_index}.tab_blocked_words"))
      expect(response.body).to include(I18n.t("#{cm_index}.blocked_words_heading"))
    end

    it "shows health tab when tab=health" do
      get admin_content_moderation_index_path(tab: "health")
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("#{cm_index}.health_heading"))
      expect(response.body).to include(I18n.t("#{cm_index}.run_manual_check"))
    end
  end

  describe "POST trigger_profanity_update" do
    it "enqueues profanity list update and redirects with notice" do
      expect(ProfanityListUpdateJob).to receive(:perform_async)
      post trigger_profanity_update_admin_content_moderation_index_path
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "profanity_list"))
      expect(flash[:notice]).to be_present
    end

    it "returns turbo stream and refreshes profanity wrap" do
      expect(ProfanityListUpdateJob).to receive(:perform_async)
      post trigger_profanity_update_admin_content_moderation_index_path(format: :turbo_stream)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_content_moderation_profanity_wrap")
    end
  end

  describe "POST run_health_check" do
    it "enqueues moderation health check and redirects with notice" do
      expect(ContentModerationHealthCheckJob).to receive(:perform_async)
      post run_health_check_admin_content_moderation_index_path
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "health"))
      expect(flash[:notice]).to be_present
    end

    it "returns turbo stream and refreshes health wrap" do
      expect(ContentModerationHealthCheckJob).to receive(:perform_async)
      post run_health_check_admin_content_moderation_index_path(format: :turbo_stream)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_content_moderation_health_wrap")
    end
  end

  describe "POST add_blocked_word" do
    it "adds a custom blocked word and redirects" do
      expect {
        post add_blocked_word_admin_content_moderation_index_path, params: { word: "custombad", category: "profanity" }
      }.to change(BlockedWord, :count).by(1)
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "blocked_words"))
      expect(BlockedWord.find_by(word: "custombad")).to be_present
    end

    it "rejects blank word with alert" do
      post add_blocked_word_admin_content_moderation_index_path, params: { word: " ", category: "profanity" }
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "blocked_words"))
      expect(flash[:alert]).to be_present
    end

    it "rejects duplicate word with alert" do
      create(:blocked_word, word: "duplicateword")
      post add_blocked_word_admin_content_moderation_index_path, params: { word: "duplicateword" }
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "blocked_words"))
      expect(flash[:alert]).to be_present
    end

    it "returns turbo stream and refreshes blocked words wrap" do
      expect {
        post add_blocked_word_admin_content_moderation_index_path(format: :turbo_stream),
          params: { word: "streamadd", category: "profanity" }
      }.to change(BlockedWord, :count).by(1)

      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_content_moderation_blocked_words_wrap")
      expect(response.body).to include("streamadd")
    end
  end

  describe "DELETE remove_blocked_word" do
    it "removes blocked word and redirects" do
      bw = create(:blocked_word, word: "toremove")
      expect {
        delete remove_blocked_word_admin_content_moderation_index_path(bw.id)
      }.to change(BlockedWord, :count).by(-1)
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "blocked_words"))
    end

    it "redirects with alert when word not found" do
      delete remove_blocked_word_admin_content_moderation_index_path(999_999)
      expect(response).to redirect_to(admin_content_moderation_index_path(tab: "blocked_words"))
      expect(flash[:alert]).to be_present
    end

    it "returns turbo stream when removing a word" do
      bw = create(:blocked_word, word: "streamremove")
      expect {
        delete remove_blocked_word_admin_content_moderation_index_path(bw.id, format: :turbo_stream)
      }.to change(BlockedWord, :count).by(-1)

      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_content_moderation_blocked_words_wrap")
    end
  end

  describe "moderatable allow-list" do
    it "rejects disallowed content_type on approve" do
      fr = create(:feature_request)
      fr.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current)

      post approve_content_admin_content_moderation_index_path, params: {
        content_type: "Guild",
        content_id: fr.id
      }

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:alert]).to eq(I18n.t("admin.content_moderation.flash.invalid_content_type"))
      expect(fr.reload.moderation_status).to eq("pending")
    end

    it "rejects non-numeric content_id on approve" do
      fr = create(:feature_request)
      fr.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current)

      post approve_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequest",
        content_id: "abc"
      }

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:alert]).to eq(I18n.t("admin.content_moderation.flash.invalid_content_id"))
    end

    it "redirects with alert when content is missing" do
      post approve_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequest",
        content_id: 9_999_999_999
      }

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:alert]).to eq(I18n.t("admin.content_moderation.flash.content_not_found"))
    end
  end

  describe "POST approve_content (authenticated admin)" do
    it "approves a pending FeatureRequest and writes an audit row" do
      fr = create(:feature_request)
      fr.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current)

      expect {
        post approve_content_admin_content_moderation_index_path, params: {
          content_type: "FeatureRequest",
          content_id: fr.id,
          moderation_notes: "Looks fine"
        }
      }.to change {
        ModerationAuditLog.where(action: "approve", content_type: "FeatureRequest", content_id: fr.id).count
      }.by(1)

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:notice]).to eq(I18n.t("admin.content_moderation.flash.approve"))
      expect(fr.reload.moderation_status).to eq("approved")
      expect(fr.moderation_reason).to be_nil
    end
  end

  describe "POST hide_content (authenticated admin)" do
    it "marks a pending FeatureRequest as rejected with the given reason" do
      fr = create(:feature_request)
      fr.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current)

      post hide_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequest",
        content_id: fr.id,
        moderation_reason: "spam",
        moderation_notes: "Obvious spam"
      }

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:notice]).to eq(I18n.t("admin.content_moderation.flash.hide"))
      fr.reload
      expect(fr.moderation_status).to eq("rejected")
      expect(fr.moderation_reason).to eq("spam")
    end
  end

  describe "POST soft_delete_content (authenticated admin)" do
    it "sets deleted_at on a FeatureRequestComment" do
      fr = create(:feature_request)
      comment = create(:feature_request_comment, feature_request: fr)
      comment.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current, deleted_at: nil)

      expect {
        post soft_delete_content_admin_content_moderation_index_path, params: {
          content_type: "FeatureRequestComment",
          content_id: comment.id
        }
      }.to change { comment.reload.deleted_at }.from(nil)

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:notice]).to eq(I18n.t("admin.content_moderation.flash.soft_delete"))
    end

    it "sets deleted_at on a FeatureRequest" do
      fr = create(:feature_request)
      fr.update_columns(moderation_status: "pending", moderation_flagged_at: Time.current, deleted_at: nil)

      expect {
        post soft_delete_content_admin_content_moderation_index_path, params: {
          content_type: "FeatureRequest",
          content_id: fr.id
        }
      }.to change { fr.reload.deleted_at }.from(nil)

      expect(response).to redirect_to(admin_content_moderation_index_path)
      expect(flash[:notice]).to eq(I18n.t("admin.content_moderation.flash.soft_delete"))
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin for index" do
      get admin_content_moderation_index_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for trigger_profanity_update" do
      expect(ProfanityListUpdateJob).not_to receive(:perform_async)
      post trigger_profanity_update_admin_content_moderation_index_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for add_blocked_word" do
      expect {
        post add_blocked_word_admin_content_moderation_index_path, params: { word: "unauthblocked", category: "profanity" }
      }.not_to change(BlockedWord, :count)
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for remove_blocked_word" do
      bw = create(:blocked_word, word: "unauthremove")
      expect {
        delete remove_blocked_word_admin_content_moderation_index_path(bw.id)
      }.not_to change(BlockedWord, :count)
      expect(response).to redirect_to(admin_login_path)
      expect(BlockedWord.exists?(bw.id)).to be true
    end

    it "requires admin for run_health_check" do
      expect(ContentModerationHealthCheckJob).not_to receive(:perform_async)
      post run_health_check_admin_content_moderation_index_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for approve_content" do
      fr = create(:feature_request)
      fr.update_column(:moderation_status, "pending")

      post approve_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequest",
        content_id: fr.id
      }

      expect(response).to redirect_to(admin_login_path)
      expect(fr.reload.moderation_status).to eq("pending")
    end

    it "requires admin for hide_content" do
      fr = create(:feature_request)
      fr.update_column(:moderation_status, "pending")

      post hide_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequest",
        content_id: fr.id,
        moderation_reason: "spam"
      }

      expect(response).to redirect_to(admin_login_path)
      expect(fr.reload.moderation_status).to eq("pending")
    end

    it "requires admin for soft_delete_content" do
      fr = create(:feature_request)
      comment = create(:feature_request_comment, feature_request: fr)
      comment.update_column(:moderation_status, "pending")
      expect(comment.deleted_at).to be_nil

      post soft_delete_content_admin_content_moderation_index_path, params: {
        content_type: "FeatureRequestComment",
        content_id: comment.id
      }

      expect(response).to redirect_to(admin_login_path)
      expect(comment.reload.deleted_at).to be_nil
    end
  end
end

