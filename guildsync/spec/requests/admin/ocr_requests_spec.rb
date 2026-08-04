# frozen_string_literal: true

require "erb"
require "rails_helper"
require "csv"

RSpec.describe "Admin::OcrRequests", type: :request do
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

  describe "GET /admin/ocr-requests" do
    it "returns success and shows OCR request counts page" do
      get admin_ocr_requests_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_ocr_requests_index_main"))
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.title"))
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.stats.total_all_time"))
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.stats.this_month"))
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.users_heading"))
    end

    it "renders frame-only body when Turbo-Frame requests index main" do
      get admin_ocr_requests_path,
        headers: { "Turbo-Frame" => Admin::OcrRequestsController::OCR_REQUESTS_INDEX_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_ocr_requests_index_main"))
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.stats.total_all_time"))
      expect(response.body).not_to include(I18n.t("admin.ocr_requests.index.title"))
    end

    it "includes hard stop and monitoring stats when OCR tables exist" do
      get admin_ocr_requests_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.stats.users_near_limit")) if defined?(User) && User.respond_to?(:near_ocr_limit)
      expect(response.body).to include(I18n.t("admin.ocr_requests.index.table.hard_stop")) if defined?(OcrRequest)
    end
  end

  describe "GET /admin/ocr-requests/:user_id" do
    let!(:user) { create(:user) }

    it "returns success and shows user OCR usage" do
      get admin_ocr_request_user_path(user)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(user.email)
      expect(response.body).to include(%(turbo-frame id="admin_ocr_requests_show_main"))
      expect(response.body).to include('id="admin_ocr_user_show_flash"')
      expect(response.body).to include('id="admin_ocr_user_summary_cards"')
    end

    it "renders frame-only body when Turbo-Frame requests show main" do
      get admin_ocr_request_user_path(user),
        headers: { "Turbo-Frame" => Admin::OcrRequestsController::OCR_REQUESTS_SHOW_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_ocr_requests_show_main"))
      expect(response.body).to include('id="admin_ocr_user_summary_cards"')
      expect(response.body).not_to include(I18n.t("admin.ocr_requests.show.title", email: user.email))
    end
  end

  describe "GET /admin/ocr-requests/export" do
    it "returns CSV with i18n header row" do
      get admin_ocr_requests_export_path
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq(Mime[:csv].to_s)

      expected_headers = [
        I18n.t("admin.ocr_requests.export.email"),
        I18n.t("admin.ocr_requests.export.username"),
        I18n.t("admin.ocr_requests.export.plan"),
        I18n.t("admin.ocr_requests.export.used_period"),
        I18n.t("admin.ocr_requests.export.limit"),
        I18n.t("admin.ocr_requests.export.locked"),
        I18n.t("admin.ocr_requests.export.unlocked"),
        I18n.t("admin.ocr_requests.export.last_reset")
      ]
      first_row = CSV.parse_line(response.body.each_line.first)
      expect(first_row).to eq(expected_headers)
    end
  end

  describe "POST /admin/ocr-requests/:user_id/adjust" do
    let!(:user) { create(:user) }

    it "adjusts period usage with reason and shows translated notice" do
      skip "User has no OCR billing columns" unless User.column_names.include?("ocr_requests_used_this_period")

      user.update_columns(ocr_requests_used_this_period: 5, ocr_billing_plan: "trial")

      expect do
        post admin_ocr_request_adjust_path(user), params: { delta: -2, reason: "Spec adjustment" }
      end.to change { user.reload.ocr_requests_used_this_period }.from(5).to(3)

      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.usage_updated"))
    end

    it "redirects with alert when reason is blank" do
      skip "User has no OCR billing columns" unless User.column_names.include?("ocr_requests_used_this_period")

      post admin_ocr_request_adjust_path(user), params: { delta: 1, reason: "   " }
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:alert]).to eq(I18n.t("admin.ocr_requests.flash.reason_required"))
    end

    it "returns turbo-stream refresh on success and alert stream when reason blank" do
      skip "User has no OCR billing columns" unless User.column_names.include?("ocr_requests_used_this_period")

      user.update_columns(ocr_requests_used_this_period: 5, ocr_billing_plan: "trial")

      post admin_ocr_request_adjust_path(user),
        params: { delta: -1, reason: "Turbo spec" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_ocr_user_summary_cards")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.ocr_requests.flash.usage_updated"))
      )

      post admin_ocr_request_adjust_path(user),
        params: { delta: 1, reason: "   " },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response.body).to include('action="update"', "admin_ocr_user_show_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.ocr_requests.flash.reason_required"))
      )
    end
  end

  describe "POST /admin/ocr-requests/bulk" do
    let!(:user) { create(:user) }

    it "bulk lock redirects with notice" do
      post admin_ocr_requests_bulk_path, params: { bulk_action: "lock", user_ids: [ user.id ] }
      expect(response).to redirect_to(admin_ocr_requests_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.ocr_hard_locked).to be true
    end

    it "redirects with alert when no user ids selected" do
      post admin_ocr_requests_bulk_path, params: { bulk_action: "lock", user_ids: [] }
      expect(response).to redirect_to(admin_ocr_requests_path)
      expect(flash[:alert]).to eq(I18n.t("admin.ocr_requests.flash.select_at_least_one"))
    end

    it "redirects with alert for unknown bulk action" do
      post admin_ocr_requests_bulk_path, params: { bulk_action: "invalid", user_ids: [ user.id ] }
      expect(response).to redirect_to(admin_ocr_requests_path)
      expect(flash[:alert]).to eq(I18n.t("admin.ocr_requests.flash.unknown_bulk_action"))
    end

    it "bulk reset clears period usage for selected users" do
      skip "User has no OCR billing columns" unless User.column_names.include?("ocr_requests_used_this_period")

      user.update_columns(ocr_requests_used_this_period: 9, ocr_billing_plan: "trial")

      post admin_ocr_requests_bulk_path, params: { bulk_action: "reset", user_ids: [ user.id ] }
      expect(response).to redirect_to(admin_ocr_requests_path)
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.bulk_reset", count: 1))
      expect(user.reload.ocr_requests_used_this_period).to eq(0)
    end

    it "returns turbo stream and replaces index main wrap on bulk lock" do
      skip "User has no ocr_hard_locked column" unless User.column_names.include?("ocr_hard_locked")

      post admin_ocr_requests_bulk_path(format: :turbo_stream),
        params: { bulk_action: "lock", user_ids: [ user.id ] }
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_ocr_requests_index_main_wrap")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.ocr_requests.flash.bulk_locked", count: 1)))
      expect(user.reload.ocr_hard_locked).to be true
    end

    it "returns turbo stream with alert when no users selected" do
      post admin_ocr_requests_bulk_path(format: :turbo_stream),
        params: { bulk_action: "lock", user_ids: [] }
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_ocr_requests_index_flash")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.ocr_requests.flash.select_at_least_one")))
    end
  end

  describe "POST /admin/ocr-requests/:user_id/toggle_lock" do
    let!(:user) { create(:user) }

    it "locks then unlocks OCR with translated flashes" do
      skip "User has no ocr_hard_locked column" unless User.column_names.include?("ocr_hard_locked")

      expect(user.ocr_hard_locked).to be false

      post admin_ocr_request_toggle_lock_path(user)
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.user_locked"))
      expect(user.reload.ocr_hard_locked).to be true

      post admin_ocr_request_toggle_lock_path(user)
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.user_unlocked"))
      expect(user.reload.ocr_hard_locked).to be false
    end

    it "returns turbo-stream refresh with updated lock controls" do
      skip "User has no ocr_hard_locked column" unless User.column_names.include?("ocr_hard_locked")

      post admin_ocr_request_toggle_lock_path(user), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_ocr_user_actions_panel")
      expect(response.body).to include(I18n.t("admin.ocr_requests.show.unlock_ocr"))
    end
  end

  describe "POST /admin/ocr-requests/:user_id/toggle_unlock" do
    let!(:user) { create(:user) }

    it "grants then revokes unlock override with translated flashes" do
      skip "User has no ocr_unlocked column" unless User.column_names.include?("ocr_unlocked")

      expect(user.ocr_unlocked).to be false

      post admin_ocr_request_toggle_unlock_path(user)
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.unlock_granted"))
      expect(user.reload.ocr_unlocked).to be true

      post admin_ocr_request_toggle_unlock_path(user)
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.unlock_revoked"))
      expect(user.reload.ocr_unlocked).to be false
    end
  end

  describe "POST /admin/ocr-requests/:user_id/reset_period" do
    let!(:user) { create(:user) }

    it "zeros period usage with translated notice" do
      skip "User has no OCR billing columns" unless User.column_names.include?("ocr_requests_used_this_period")

      user.update_columns(ocr_requests_used_this_period: 4, ocr_billing_plan: "basic")

      post admin_ocr_request_reset_period_path(user)
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.monthly_reset"))
      expect(user.reload.ocr_requests_used_this_period).to eq(0)
    end
  end

  describe "PATCH /admin/ocr-requests/:user_id/notes" do
    let!(:user) { create(:user) }

    it "persists admin OCR notes with translated notice" do
      skip "User has no ocr_notes column" unless User.column_names.include?("ocr_notes")

      patch admin_ocr_request_notes_path(user), params: { ocr_notes: "VIP — watch usage" }
      expect(response).to redirect_to(admin_ocr_request_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.ocr_requests.flash.notes_updated"))
      expect(user.reload.ocr_notes).to eq("VIP — watch usage")
    end
  end

  describe "authentication" do
    before { delete "/admin/logout" }

    it "requires admin for index" do
      get admin_ocr_requests_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for show" do
      get admin_ocr_request_user_path(create(:user))
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for export" do
      get admin_ocr_requests_export_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for toggle_lock" do
      u = create(:user)
      post admin_ocr_request_toggle_lock_path(u)
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for reset_period" do
      u = create(:user)
      post admin_ocr_request_reset_period_path(u)
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for notes update" do
      u = create(:user)
      patch admin_ocr_request_notes_path(u), params: { ocr_notes: "x" }
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
