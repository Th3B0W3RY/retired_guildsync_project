# frozen_string_literal: true

require "erb"
require "rails_helper"

RSpec.describe "Admin::Errors", type: :request do
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

  describe "GET /admin/errors" do
    let!(:unresolved_error) do
      ErrorLog.create!(
        error_class: "StandardError",
        message: "Test error message",
        occurred_at: 1.hour.ago
      )
    end

    let!(:resolved_error) do
      ErrorLog.create!(
        error_class: "AnotherError",
        message: "Resolved error",
        occurred_at: 2.hours.ago,
        resolved_at: 1.hour.ago,
        resolved_by: admin_email
      )
    end

    it "lists all errors in two columns (unresolved and resolved)" do
      get admin_errors_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(unresolved_error.error_class)
      expect(response.body).to include(resolved_error.error_class)
      expect(response.body).to include(I18n.t("admin.errors.index.unresolved_title", count: 1))
      expect(response.body).to include(I18n.t("admin.errors.index.resolved_title", count: 1))
      expect(response.body).to include('id="admin_errors_flash"')
      expect(response.body).to include('id="admin_errors_columns"')
    end

    it "shows unresolved errors in the first column" do
      get admin_errors_path
      expect(response.body).to include(unresolved_error.error_class)
      expect(response.body).to include("Test error message")
    end

    it "shows resolved errors in the second column" do
      get admin_errors_path
      expect(response.body).to include(resolved_error.error_class)
      expect(response.body).to include("Resolved error")
    end

    it "returns frame-only HTML when Turbo-Frame targets main index" do
      get admin_errors_path,
        headers: { "Turbo-Frame" => Admin::ErrorsController::ERRORS_INDEX_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::ErrorsController::ERRORS_INDEX_MAIN_FRAME}"))
      expect(response.body).to include(unresolved_error.error_class)
      expect(response.body).not_to include(I18n.t("admin.errors.index.page_title"))
    end
  end

  describe "GET /admin/errors/:id" do
    let!(:error) do
      ErrorLog.create!(
        error_class: "StandardError",
        message: "Test error message",
        backtrace: "backtrace line 1\nbacktrace line 2",
        context: { "user_id" => 1, "action" => "test" },
        occurred_at: 1.hour.ago
      )
    end

    it "shows error details" do
      get admin_error_path(error)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(error.error_class)
      expect(response.body).to include(error.message)
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get admin_error_path(error),
        headers: { "Turbo-Frame" => Admin::ErrorsController::ERRORS_SHOW_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_errors_show_main"))
      expect(response.body).to include(error.message)
    end
  end

  describe "POST /admin/errors/:id/resolve" do
    let!(:error) do
      ErrorLog.create!(
        error_class: "StandardError",
        message: "Test error",
        occurred_at: 1.hour.ago
      )
    end

    it "marks error as resolved" do
      expect(error.resolved?).to be false
      post resolve_admin_error_path(error)
      expect(response).to redirect_to(admin_error_path(error))
      expect(flash[:notice]).to eq(I18n.t("admin.errors.flash.resolved"))
      error.reload
      expect(error.resolved?).to be true
      expect(error.resolved_by).to eq(admin_email)
    end

    it "returns turbo_stream refresh on mark resolved (show page)" do
      expect(error.resolved?).to be false
      post resolve_admin_error_path(error),
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="update"', "admin_error_show_flash")
      expect(response.body).to include('action="replace"', "admin_error_show_main")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.errors.flash.resolved"))
      )
      expect(response.body).to include(I18n.t("admin.errors.show.resolved_at"))
      error.reload
      expect(error.resolved?).to be true
      expect(error.resolved_by).to eq(admin_email)
    end
  end

  describe "DELETE /admin/errors/:id" do
    let!(:error) do
      ErrorLog.create!(
        error_class: "StandardError",
        message: "To be deleted",
        occurred_at: 1.hour.ago
      )
    end

    it "deletes the error" do
      expect { delete admin_error_path(error) }.to change(ErrorLog, :count).by(-1)
      expect(response).to redirect_to(admin_errors_path)
      expect(flash[:notice]).to eq(I18n.t("admin.errors.flash.deleted"))
    end

    it "returns turbo-stream column refresh when referer is errors index" do
      delete admin_error_path(error),
        headers: {
          "Accept" => Mime[:turbo_stream].to_s,
          "HTTP_REFERER" => admin_errors_url
        }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_errors_columns")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.errors.flash.deleted"))
      )
    end
  end

  describe "POST /admin/errors/bulk" do
    let!(:err1) { ErrorLog.create!(error_class: "E1", message: "M1", occurred_at: 1.hour.ago) }
    let!(:err2) { ErrorLog.create!(error_class: "E2", message: "M2", occurred_at: 1.hour.ago) }

    it "bulk resolves selected errors" do
      post bulk_admin_errors_path, params: { bulk_action: "resolve", error_ids: [ err1.id, err2.id ] }
      expect(response).to redirect_to(admin_errors_path)
      expect(flash[:notice]).to eq(I18n.t("admin.errors.flash.bulk_resolved", count: 2))
      expect(err1.reload.resolved?).to be true
      expect(err2.reload.resolved?).to be true
    end

    it "bulk deletes selected errors" do
      expect do
        post bulk_admin_errors_path, params: { bulk_action: "delete", error_ids: [ err1.id ] }
      end.to change(ErrorLog, :count).by(-1)
      expect(response).to redirect_to(admin_errors_path)
      expect(flash[:notice]).to eq(I18n.t("admin.errors.flash.bulk_deleted", count: 1))
    end

    it "redirects with alert when no ids selected" do
      post bulk_admin_errors_path, params: { bulk_action: "resolve", error_ids: [] }
      expect(response).to redirect_to(admin_errors_path)
      expect(flash[:alert]).to eq(I18n.t("admin.errors.flash.select_one"))
    end

    it "redirects with alert for unknown bulk action" do
      post bulk_admin_errors_path, params: { bulk_action: "unknown", error_ids: [ err1.id ] }
      expect(response).to redirect_to(admin_errors_path)
      expect(flash[:alert]).to eq(I18n.t("admin.errors.flash.unknown_bulk_action"))
    end

    it "returns turbo-stream refresh on bulk resolve" do
      post bulk_admin_errors_path,
        params: { bulk_action: "resolve", error_ids: [ err1.id, err2.id ] },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_errors_columns")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.errors.flash.bulk_resolved", count: 2))
      )
    end

    it "returns turbo-stream alert when no ids selected" do
      post bulk_admin_errors_path,
        params: { bulk_action: "resolve", error_ids: [] },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_errors_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.errors.flash.select_one"))
      )
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin authentication" do
      get admin_errors_path
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
