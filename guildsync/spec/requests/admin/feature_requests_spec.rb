# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::FeatureRequests", type: :request do
  let(:admin_email) { "admin@feature-requests-spec.test" }
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

  let(:user) { create(:user) }
  let!(:feature_request) { create(:feature_request, user: user, is_pinned: false) }

  describe "GET /admin/roadmap" do
    it "renders the admin panel title and wraps the board in the main turbo frame" do
      get admin_feature_requests_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("roadmap.admin.panel_title"))
      expect(response.body).to include(%(turbo-frame id="admin_feature_requests_main"))
      expect(response.body).to include("admin_feature_requests_flash")
      expect(response.body).to include("admin_roadmap_column_list_#{feature_request.status}")
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get admin_feature_requests_path,
        headers: { "Turbo-Frame" => Admin::FeatureRequestsController::FEATURE_REQUESTS_INDEX_MAIN_FRAME }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(turbo-frame id="admin_feature_requests_main"))
      expect(response.body).to include(feature_request.title)
      expect(response.body).not_to include(I18n.t("roadmap.admin.panel_title"))
    end
  end

  describe "GET /admin/roadmap/:id/edit" do
    it "renders page chrome outside the edit turbo frame and the form inside" do
      get edit_admin_feature_request_path(feature_request)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(turbo-frame id="admin_feature_requests_edit_main"))
      expect(response.body).to include(%(action="#{admin_feature_request_path(feature_request)}"))
      heading = "#{I18n.t('roadmap.admin.edit')}: #{feature_request.title}"
      expect(response.body).to include(heading)
      expect(response.body).to include(I18n.t("roadmap.create_title_label"))
    end

    it "renders frame-only body when Turbo-Frame requests edit main" do
      get edit_admin_feature_request_path(feature_request),
        headers: { "Turbo-Frame" => Admin::FeatureRequestsController::FEATURE_REQUESTS_EDIT_MAIN_FRAME }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(turbo-frame id="admin_feature_requests_edit_main"))
      expect(response.body).to include(%(action="#{admin_feature_request_path(feature_request)}"))
      expect(response.body).not_to include("#{I18n.t('roadmap.admin.edit')}: #{feature_request.title}")
    end
  end

  describe "PATCH /admin/roadmap/:id/pin" do
    it "returns turbo-stream replace card and flash when toggling pin on" do
      expect(feature_request.is_pinned).to be(false)
      patch pin_admin_feature_request_path(feature_request), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_feature_request_card_#{feature_request.id}")
      expect(response.body).to include(I18n.t("roadmap.admin.pinned"))
      expect(feature_request.reload.is_pinned).to be(true)
    end

    it "returns turbo-stream with unpinned message when toggling off" do
      feature_request.update!(is_pinned: true)
      patch pin_admin_feature_request_path(feature_request), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("roadmap.admin.unpinned"))
      expect(feature_request.reload.is_pinned).to be(false)
    end
  end

  describe "DELETE /admin/roadmap/:id" do
    it "returns turbo-stream remove, flash, and column empty hint when last request in that status" do
      fr_id = feature_request.id
      delete admin_feature_request_path(feature_request), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="remove"', "admin_feature_request_card_#{fr_id}")
      expect(response.body).to include(I18n.t("roadmap.admin.deleted"))
      expect(response.body).to include("admin_roadmap_column_list_considering")
      expect(response.body).to include(I18n.t("roadmap.empty_column"))
      expect { FeatureRequest.find(fr_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns turbo-stream remove without appending empty when another request stays in column" do
      create(:feature_request, user: user, status: "considering")
      fr_id = feature_request.id
      delete admin_feature_request_path(feature_request), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="remove"', "admin_feature_request_card_#{fr_id}")
      expect(response.body).not_to include('action="append"')
    end
  end

  describe "PATCH /admin/roadmap/:id/move" do
    it "returns turbo-stream repositioning card when moving to an empty column" do
      expect(FeatureRequest.where(status: "in_progress").count).to eq(0)
      patch move_admin_feature_request_path(feature_request),
            params: { status: "in_progress" },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(feature_request.reload.status).to eq("in_progress")
      expect(response.body).to include("admin_roadmap_empty_in_progress")
      expect(response.body).to include("admin_roadmap_empty_considering")
      expect(response.body).to include('action="append"', "admin_roadmap_column_list_in_progress")
      expect(response.body).to include(I18n.t("roadmap.admin.moved"))
    end

    it "does not remove target empty id when destination column already has cards" do
      create(:feature_request, user: user, status: "in_progress")
      patch move_admin_feature_request_path(feature_request),
            params: { status: "in_progress" },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(feature_request.reload.status).to eq("in_progress")
      expect(response.body).not_to include("admin_roadmap_empty_in_progress")
    end

    it "returns turbo-stream flash only when status unchanged" do
      patch move_admin_feature_request_path(feature_request),
            params: { status: "considering" },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("roadmap.admin.moved"))
      expect(response.body).not_to include('action="append"')
    end

    it "returns 422 turbo-stream for invalid status" do
      patch move_admin_feature_request_path(feature_request),
            params: { status: "not_a_real_status" },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("roadmap.admin.invalid_status"))
    end
  end
end
